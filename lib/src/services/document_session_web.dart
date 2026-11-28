import 'dart:async';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';

import '../core/clock.dart';
import '../models/document.dart';
import 'document_files.dart';
import 'document_rows.dart';
import 'document_session.dart';
import 'recovery_snapshots.dart';
import 'recovery_snapshots_web.dart';
import 'schema.dart';
import 'sqlite_backend_web.dart';

/// The browser's session (web build, for previews and feedback).
///
/// The working database lives in IndexedDB and is its own autosave: every
/// write is kept by the browser, so [save] and [flush] only make sure the
/// pages reached storage. A document comes in by upload ([openDocument],
/// with the bytes [read] hands over) and goes out by download ([saveAs],
/// handed to [download]). [document] is the last file name it went out or
/// came in under; [dirty] means edits since then. There is no other device
/// to compare with, so [resume] answers [RemoteUnbound] and there are no
/// snapshots.
class BrowserDocumentSession implements DocumentSessionBase {
  BrowserDocumentSession({
    required CommonDatabase writer,
    required this.read,
    required this.download,
    this.clock = systemClock,
  }) : _writer = writer {
    _writes = writer.updatesSync.listen((_) => _onWrite());
  }

  final CommonDatabase _writer;

  /// The bytes of a picked document, or null when there are none.
  final Future<Uint8List?> Function(DocumentRef ref) read;

  /// Hands a finished document to the browser as a download.
  final void Function(String name, Uint8List bytes) download;

  final Clock clock;

  DocumentRef? _ref;
  bool _dirty = false;
  bool _importing = false;
  List<RecentDocument> _recents = const [];
  Object? _lastSaveError;
  StreamSubscription<SqliteUpdate>? _writes;
  final _changes = StreamController<DocumentChange>.broadcast(sync: true);

  @override
  DocumentRef? get document => _ref;

  @override
  bool get dirty => _dirty;

  @override
  List<RecentDocument> get recents => _recents;

  @override
  Object? get lastSaveError => _lastSaveError;

  @override
  Stream<DocumentChange> get changes => _changes.stream;

  @override
  SnapshotShelf get snapshots => const NoSnapshots();

  void _onWrite() {
    if (_importing || _dirty) return;
    _dirty = true;
    scheduleMicrotask(() => _emit(DocumentChange.state));
  }

  @override
  Future<void> flush() => flushSqlite();

  @override
  Future<void> save() => flushSqlite();

  @override
  Future<void> saveAs(DocumentRef ref) async {
    await saveAsPlaced((_, _) async => ref, name: ref.name);
  }

  @override
  Future<bool> saveAsPlaced(
    DocumentPlacer place, {
    required String name,
  }) async {
    final file = documentFileName(name);
    try {
      download(file, exportBytes(_writer));
    } catch (e) {
      _lastSaveError = e;
      _emit(DocumentChange.state);
      rethrow;
    }
    _bind(DocumentRef(location: 'download:$file', name: file));
    return true;
  }

  @override
  Future<void> openDocument(DocumentRef ref) async {
    final bytes = await read(ref);
    if (bytes == null) {
      throw DocumentUnreachableException(ref, 'no file was picked');
    }
    _replaceWith(bytes, ref.name);
    _bind(ref);
  }

  @override
  Future<RemoteCheck> resume() async => const RemoteUnbound();

  @override
  Future<void> startUntitled() async {
    _replaceWith(null, 'new');
    _ref = null;
    _dirty = false;
    _emit(DocumentChange.state);
  }

  @override
  Future<void> restoreSnapshot(String snapshotPath) =>
      throw UnsupportedError('The web build keeps no snapshots.');

  @override
  void forgetRecent(DocumentRef ref) {
    _recents = [
      for (final r in _recents)
        if (r.ref != ref) r,
    ];
    _emit(DocumentChange.state);
  }

  @override
  Future<void> close() async {
    await _writes?.cancel();
    await _changes.close();
  }

  /// Replaces the working rows with the document in [bytes] (null: a
  /// fresh, empty one). Throws [NotADocumentException] or
  /// `SchemaTooNewException`; then nothing changed.
  void _replaceWith(Uint8List? bytes, String label) {
    const path = '/incoming.anisched';
    if (bytes != null) putMemoryFile(path, bytes);
    final CommonDatabase doc;
    try {
      doc = openMemoryFile(path);
    } on SqliteException catch (e) {
      deleteMemoryFile(path);
      throw NotADocumentException(label, e.message);
    }
    try {
      if (bytes == null) {
        doc.execute('PRAGMA application_id = $documentApplicationId');
        migrate(doc);
      } else {
        checkAndMigrateDocument(doc, label);
      }
      _importing = true;
      try {
        copyAllRows(doc, _writer);
      } finally {
        _importing = false;
      }
    } finally {
      doc.close();
      deleteMemoryFile(path);
    }
    _emit(DocumentChange.content);
  }

  void _bind(DocumentRef ref) {
    _ref = ref;
    _dirty = false;
    _lastSaveError = null;
    _recents = touchRecent(_recents, ref, clock());
    _emit(DocumentChange.state);
  }

  void _emit(DocumentChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }
}

/// [writer]'s database as one self-contained document file: a fresh
/// in-memory database at the latest schema, stamped with
/// [documentApplicationId], given every row.
Uint8List exportBytes(CommonDatabase writer) {
  const path = '/outgoing.anisched';
  deleteMemoryFile(path);
  final out = openMemoryFile(path);
  try {
    out
      ..execute('PRAGMA journal_mode = DELETE')
      ..execute('PRAGMA application_id = $documentApplicationId');
    migrate(out);
    copyAllRows(writer, out);
  } finally {
    out.close();
  }
  final bytes = memoryFileBytes(path)!;
  deleteMemoryFile(path);
  return bytes;
}
