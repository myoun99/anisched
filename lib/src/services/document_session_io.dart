import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/common.dart';

import '../core/clock.dart';
import '../models/document.dart';
import 'document_codec.dart';
import 'document_files.dart';
import 'document_session.dart';
import 'recovery_snapshots.dart';

/// The one owner of "which document is this, and is it saved".
///
/// The working database stays in the app container; the document file is
/// written whole ([exportDocument] → [DocumentFiles.replaceFrom]) and read
/// whole ([DocumentFiles.readInto] → [importDocumentInto]). Edits are seen
/// through the writer's update hook and saved [autosaveDelay] after the
/// last one; [flush] saves now (app going to background or closing).
/// Untitled = no document bound: the working database is the only copy
/// until [saveAs].
///
/// Jobs run one at a time in call order. Lives below the UI: no widgets.
class DocumentSession implements DocumentSessionBase {
  DocumentSession._(
    this._writer,
    this.workingPath,
    this.folder,
    this._files,
    this._clock,
    this.autosaveDelay,
    this.snapshots,
  );

  /// Loads the session state kept in [folder] (the app container), clears
  /// leftovers from the last run and drops snapshots older than 30 days.
  static Future<DocumentSession> open({
    required CommonDatabase writer,
    required String workingPath,
    required String folder,
    required DocumentFiles files,
    Clock clock = systemClock,
    Duration autosaveDelay = const Duration(seconds: 3),
  }) async {
    final session = DocumentSession._(
      writer,
      workingPath,
      folder,
      files,
      clock,
      autosaveDelay,
      RecoverySnapshots(_join(folder, 'recovery'), clock: clock),
    );
    session._load();
    final staging = Directory(session._stagingFolder);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    session.snapshots.collectGarbage();
    final ref = session._ref;
    if (ref != null) {
      try {
        session._ref = await files.reopen(ref);
        session._persist();
      } on DocumentUnreachableException {
        // Kept bound: [resume] reports it, the user decides.
      }
    }
    session._writes = writer.updatesSync.listen((_) => session._onWrite());
    if (session._dirty && session._ref != null) session._scheduleAutosave();
    return session;
  }

  final CommonDatabase _writer;

  /// The working database file in the app container.
  final String workingPath;

  /// The app container folder holding state, staging and snapshots.
  final String folder;

  final DocumentFiles _files;
  final Clock _clock;

  /// How long after the last edit an autosave runs.
  final Duration autosaveDelay;

  @override
  final RecoverySnapshots snapshots;

  DocumentRef? _ref;
  DocumentFingerprint? _fingerprint;
  bool _dirty = false;
  List<RecentDocument> _recents = const [];
  Object? _lastSaveError;

  int _edits = 0;
  int _mismatches = 0;
  bool _importing = false;
  int _staged = 0;
  Timer? _timer;
  StreamSubscription<SqliteUpdate>? _writes;
  Future<void> _tail = Future.value();
  final _changes = StreamController<DocumentChange>.broadcast(sync: true);

  /// The bound document, or null while untitled.
  @override
  DocumentRef? get document => _ref;

  /// The document as last written or read by this device.
  DocumentFingerprint? get fingerprint => _fingerprint;

  /// The working database has edits the document does not have yet.
  @override
  bool get dirty => _dirty;

  /// Recently opened or saved documents, newest first.
  @override
  List<RecentDocument> get recents => _recents;

  /// Why the last autosave failed, cleared by the next successful save.
  @override
  Object? get lastSaveError => _lastSaveError;

  @override
  Stream<DocumentChange> get changes => _changes.stream;

  String get _statePath => _join(folder, 'document.json');
  String get _stagingFolder => _join(folder, 'staging');

  String _stagingPath(String tag) => _join(
    _stagingFolder,
    '${_clock().microsecondsSinceEpoch}-${_staged++}-$tag.$documentExtension',
  );

  // ---- edits and autosave ----

  void _onWrite() {
    if (_importing) return;
    _edits++;
    if (!_dirty) {
      _dirty = true;
      // Outside the update hook, which must not be held up.
      scheduleMicrotask(() {
        _persist();
        _emit(DocumentChange.state);
      });
    }
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    if (_ref == null) return;
    _timer?.cancel();
    _timer = Timer(autosaveDelay, () {
      _timer = null;
      unawaited(
        save().catchError((Object e) {
          _lastSaveError = e;
          _emit(DocumentChange.state);
        }),
      );
    });
  }

  /// The app is leaving the screen or closing. Where the document is
  /// replaced atomically, saves now. Elsewhere (Android) it does not touch
  /// the document — a kill while the provider holds it open cuts it to
  /// nothing — the work is safe in the local database (its unsaved state
  /// kept on disk) and saved when the app is back ([resume]) or next
  /// started.
  @override
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (!_files.replacesAtomically) {
      _persist();
      return _tail;
    }
    return save();
  }

  // ---- writing ----

  /// Writes the working database to the bound document when dirty.
  /// No-op while untitled ([saveAs] picks the place).
  @override
  Future<void> save() => _serial(() async {
    final ref = _ref;
    if (ref == null || !_dirty) return;
    await _writeInPlace(ref);
  });

  /// Writes to [ref] (a place the user just picked) and binds to it.
  /// "Save" of an untitled document is this too.
  @override
  Future<void> saveAs(DocumentRef ref) async {
    await saveAsPlaced((staged, _) async {
      await _files.replaceFrom(staged, ref);
      return ref;
    }, name: ref.name);
  }

  /// Save As where the platform picks the place only once the file exists
  /// (iOS export picker, Android create-document, the macOS save panel
  /// that must mint its bookmark after the write): the finished document
  /// is staged under [name] and [place] puts it somewhere and answers
  /// where, or null when the user backed out. Answers whether it was
  /// saved; on true the session is bound to the new place.
  @override
  Future<bool> saveAsPlaced(DocumentPlacer place, {required String name}) =>
      _serial(() async {
        final ref = await _writeTo(place, name: name);
        if (ref == null) return false;
        _ref = ref;
        _recents = touchRecent(_recents, ref, _clock());
        _persist();
        _emit(DocumentChange.state);
        return true;
      });

  /// Writes the working database and hands it to [place]; null when
  /// [place] declined (nothing changed).
  ///
  /// The bytes are first kept as the document's copy of the last write
  /// (before an in-place write to [pinTo]; after a Save As placed them),
  /// and the written size is checked: a document of another size stays
  /// unsaved and is written again ([DocumentWriteMismatchException]).
  Future<DocumentRef?> _writeTo(
    DocumentPlacer place, {
    String? name,
    String? pinTo,
  }) async {
    final editsAtStart = _edits;
    final folder = Directory(_stagingPath('out'))..createSync();
    final out = _join(folder.path, documentFileName(name ?? 'Untitled'));
    final DocumentRef? ref;
    try {
      final content = await exportDocument(workingPath, out);
      if (pinTo != null) _pin(out, pinTo, content);
      // Placing may move the staged file: keep the copy first.
      final copy = pinTo == null ? '$out.keep' : null;
      if (copy != null) File(out).copySync(copy);
      ref = await place(out, documentFileName(name ?? 'Untitled'));
      if (ref == null) return null;
      if (copy != null) _pin(copy, ref.location, content);
      var stat = await _files.stat(ref);
      if (stat != null && stat.size != content.size) {
        // A provider may report the old size for a moment.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        stat = await _files.stat(ref);
      }
      if (stat != null && stat.size != content.size) {
        throw DocumentWriteMismatchException(ref, content.size, stat.size);
      }
      _writePinNotes(ref.location, content, false);
      _mismatches = 0;
      _fingerprint = DocumentFingerprint(
        size: content.size,
        hash: content.hash,
        modifiedMs: stat?.modifiedMs,
      );
    } catch (e) {
      _lastSaveError = e;
      if (e is DocumentWriteMismatchException && _mismatches++ < 2) {
        _scheduleAutosave();
      }
      _emit(DocumentChange.state);
      rethrow;
    } finally {
      try {
        folder.deleteSync(recursive: true);
      } on FileSystemException {
        // Staging is cleared at the next start.
      }
    }
    _lastSaveError = null;
    if (_edits == editsAtStart) {
      _dirty = false;
    } else {
      _scheduleAutosave(); // edited while saving
    }
    _persist();
    _emit(DocumentChange.state);
    return ref;
  }

  /// Writes to the bound [ref] in place.
  Future<void> _writeInPlace(DocumentRef ref) => _writeTo(
    (staged, _) async {
      await _files.replaceFrom(staged, ref);
      return ref;
    },
    name: ref.name,
    pinTo: ref.location,
  );

  // ---- the copy of the last write (유저 2026-11-28: a document at 0 bytes) ----
  //
  // Before the document is replaced, the bytes about to go out are kept in
  // the app container with what they are (size, hash) and whether the
  // write finished. A write cut short — the app killed while the provider
  // had the file open, cut to nothing — is then put right from this copy
  // at the next start or return ([resume]), or on request
  // ([restoreLastWritten]). Only this device's own last write is ever put
  // back, and only over an empty file or one this device was writing.

  String get _pinFolder => _join(folder, 'last-written');

  /// Where [location]'s copy lives: an FNV-1a hash of the location names
  /// it (the location itself is kept in the copy's notes).
  String _pinPath(String location) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(location)) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return _join(_pinFolder, h.toRadixString(16).padLeft(8, '0'));
  }

  /// The notes of [location]'s copy, when one is kept.
  ({int size, int hash, bool pending})? _pinOf(String location) {
    final base = _pinPath(location);
    final notes = File('$base.json');
    if (!notes.existsSync() || !File('$base.$documentExtension').existsSync()) {
      return null;
    }
    try {
      final json = jsonDecode(notes.readAsStringSync());
      if (json
          case {
            'location': final String at,
            'size': final int size,
            'hash': final int hash,
            'pending': final bool pending,
          }
          when at == location) {
        return (size: size, hash: hash, pending: pending);
      }
    } on FormatException {
      // Unreadable notes: no copy.
    }
    return null;
  }

  void _writePinNotes(String location, DocumentContent content, bool pending) {
    final notes = File('${_pinPath(location)}.json.tmp');
    notes.writeAsStringSync(
      jsonEncode({
        'location': location,
        'size': content.size,
        'hash': content.hash,
        'pending': pending,
      }),
      flush: true,
    );
    notes.renameSync('${_pinPath(location)}.json');
  }

  /// Keeps [staged] as [location]'s copy, marked as being written.
  void _pin(String staged, String location, DocumentContent content) {
    Directory(_pinFolder).createSync(recursive: true);
    final base = _pinPath(location);
    final temp = '$base.$documentExtension.tmp';
    File(staged).copySync(temp);
    File(temp).renameSync('$base.$documentExtension');
    _writePinNotes(location, content, true);
  }

  /// When [ref] is empty, or cut short while this device was writing it,
  /// writes the kept copy back. Answers whether it did.
  Future<bool> _repair(DocumentRef ref, DocumentStat? stat) async {
    final pin = _pinOf(ref.location);
    if (pin == null || stat == null) return false;
    if (stat.size != 0) {
      // Cut short while this device wrote it — unless it reads as a whole
      // document (another device saved since): then it is theirs.
      if (!pin.pending || stat.size == pin.size) return false;
      final ({String path, DocumentFingerprint fingerprint}) seen;
      try {
        seen = await _fetch(ref);
      } on Object {
        return false;
      }
      try {
        await prepareImport(seen.path);
        return false;
      } on NotADocumentException {
        // Broken: put it right below.
      } finally {
        _delete(seen.path);
      }
    }
    final copy = '${_pinPath(ref.location)}.$documentExtension';
    await _files.replaceFrom(copy, ref);
    final after = await _files.stat(ref);
    final content = (size: pin.size, hash: pin.hash);
    _writePinNotes(ref.location, content, after?.size != pin.size);
    if (after?.size != pin.size) return false;
    _fingerprint = DocumentFingerprint(
      size: pin.size,
      hash: pin.hash,
      modifiedMs: after!.modifiedMs,
    );
    _persist();
    return true;
  }

  @override
  bool hasLastWritten(DocumentRef ref) => _pinOf(ref.location) != null;

  @override
  Future<bool> restoreLastWritten(DocumentRef ref) async {
    if (_pinOf(ref.location) == null) return false;
    final copy = '${_pinPath(ref.location)}.$documentExtension';
    await _serial(() => _files.replaceFrom(copy, ref));
    await openDocument(ref);
    return true;
  }

  // ---- reading ----

  /// Opens the document at [ref] into the working database. Unsaved work is
  /// saved to the current document first, or kept as a snapshot when it
  /// cannot be. Throws [DocumentUnreachableException],
  /// [NotADocumentException] or `SchemaTooNewException`; then nothing
  /// changed.
  @override
  Future<void> openDocument(DocumentRef ref) => _serial(() async {
    final reopened = await _files.reopen(ref);
    final incoming = await _fetch(reopened);
    try {
      await prepareImport(incoming.path);
      await _keepUnsavedWork();
      _replaceContent(incoming.path);
    } finally {
      _delete(incoming.path);
    }
    _bindClean(reopened, incoming.fingerprint);
  });

  /// Checks the bound document after the app comes back (or right after
  /// launch) and reloads it when another device changed it and nothing
  /// local is unsaved.
  @override
  Future<RemoteCheck> resume() => _serial(() async {
    final ref = _ref;
    if (ref == null) return const RemoteUnbound();
    final DocumentStat? stat;
    try {
      stat = await _files.stat(ref);
    } on Object catch (e) {
      return RemoteUnreachable(e);
    }
    if (stat == null) return const RemoteMissing();
    try {
      if (await _repair(ref, stat)) {
        _emit(DocumentChange.state);
        if (_dirty) _scheduleAutosave();
        return const RemoteRepaired();
      }
    } on Object catch (e) {
      return RemoteUnreachable(e);
    }
    // Back on screen with work not yet written (flush did not write).
    if (_dirty) _scheduleAutosave();
    final known = _fingerprint;
    if (known != null && known.sameStat(stat)) return const RemoteSame();
    final ({String path, DocumentFingerprint fingerprint}) incoming;
    try {
      incoming = await _fetch(ref);
    } on Object catch (e) {
      return RemoteUnreachable(e);
    }
    final fresh = incoming.fingerprint;
    if (known != null && known.size == fresh.size && known.hash == fresh.hash) {
      _delete(incoming.path);
      _fingerprint = known.withModified(fresh.modifiedMs);
      _persist();
      return const RemoteSame();
    }
    if (_dirty) {
      final kept = snapshots.keep(incoming.path, SnapshotReason.overwritten);
      _scheduleAutosave();
      return RemoteKeptLocal(kept);
    }
    try {
      await prepareImport(incoming.path);
      _replaceContent(incoming.path);
    } on Object catch (e) {
      return RemoteUnreachable(e);
    } finally {
      _delete(incoming.path);
    }
    _bindClean(ref, fresh);
    return const RemoteReloaded();
  });

  /// Starts a new untitled document (empty catalogue, seeded presets).
  @override
  Future<void> startUntitled() => _serial(() async {
    final empty = _stagingPath('new');
    try {
      createEmptyDocumentSync(empty);
      await _keepUnsavedWork();
      _replaceContent(empty);
    } finally {
      _delete(empty);
    }
    _ref = null;
    _fingerprint = null;
    _dirty = false;
    _persist();
    _emit(DocumentChange.state);
  });

  /// Puts a recovery snapshot's content into the working database. It is
  /// an edit: the bound document gets it at the next save.
  @override
  Future<void> restoreSnapshot(String snapshotPath) => _serial(() async {
    final copy = _stagingPath('restore');
    File(snapshotPath).copySync(copy);
    try {
      await prepareImport(copy);
      if (_dirty) {
        await snapshots.takeOf(workingPath, SnapshotReason.beforeReplace);
      }
      _replaceContent(copy);
    } finally {
      _delete(copy);
    }
    _edits++;
    _dirty = true;
    _persist();
    _emit(DocumentChange.state);
    _scheduleAutosave();
  });

  /// Drops [ref] from the recent list.
  @override
  void forgetRecent(DocumentRef ref) {
    _recents = [
      for (final r in _recents)
        if (r.ref != ref) r,
    ];
    _persist();
    _emit(DocumentChange.state);
  }

  Future<({String path, DocumentFingerprint fingerprint})> _fetch(
    DocumentRef ref,
  ) async {
    final path = _stagingPath('in');
    try {
      await _files.readInto(ref, path);
      final stat = await _files.stat(ref);
      final size = File(path).lengthSync();
      final hash = await hashFile(path);
      return (
        path: path,
        fingerprint: DocumentFingerprint(
          size: size,
          hash: hash,
          modifiedMs: stat != null && stat.size == size
              ? stat.modifiedMs
              : null,
        ),
      );
    } catch (_) {
      _delete(path);
      rethrow;
    }
  }

  /// Before the working rows are replaced: save them where they belong, or
  /// keep them as a snapshot when that is not possible.
  Future<void> _keepUnsavedWork() async {
    if (!_dirty) return;
    final ref = _ref;
    if (ref != null) {
      try {
        await _writeInPlace(ref);
      } on Object {
        // Falls through to the snapshot.
      }
    }
    if (_dirty) {
      await snapshots.takeOf(workingPath, SnapshotReason.beforeReplace);
    }
  }

  void _replaceContent(String path) {
    _timer?.cancel();
    _timer = null;
    _importing = true;
    try {
      importDocumentInto(_writer, path);
    } finally {
      _importing = false;
    }
    _emit(DocumentChange.content);
  }

  void _bindClean(DocumentRef ref, DocumentFingerprint fingerprint) {
    _ref = ref;
    _fingerprint = fingerprint;
    _dirty = false;
    _lastSaveError = null;
    _recents = touchRecent(_recents, ref, _clock());
    _persist();
    _emit(DocumentChange.state);
  }

  // ---- plumbing ----

  Future<T> _serial<T>(Future<T> Function() job) {
    final next = _tail.then((_) => job());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _emit(DocumentChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  /// Stops listening and autosaving. Call [flush] first to save.
  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await _writes?.cancel();
    await _tail;
    await _changes.close();
  }

  void _load() {
    final file = File(_statePath);
    if (!file.existsSync()) return;
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    _ref = DocumentRef.fromJson(json['document']);
    _fingerprint = DocumentFingerprint.fromJson(json['fingerprint']);
    _dirty = json['dirty'] == true;
    final recents = json['recents'];
    _recents = [
      if (recents is List)
        for (final Object? r in recents)
          if (r case {'ref': final Object? json, 'openedAt': final int ms})
            if (DocumentRef.fromJson(json) case final ref?)
              (
                ref: ref,
                openedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
              ),
    ];
  }

  void _persist() {
    final json = jsonEncode({
      'document': _ref?.toJson(),
      'fingerprint': _fingerprint?.toJson(),
      'dirty': _dirty,
      'recents': [
        for (final r in _recents)
          {
            'ref': r.ref.toJson(),
            'openedAt': r.openedAt.millisecondsSinceEpoch,
          },
      ],
    });
    final temp = File('$_statePath.tmp');
    temp.writeAsStringSync(json, flush: true);
    temp.renameSync(_statePath);
  }

  static void _delete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Staging is cleared at the next start.
    }
  }
}

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
