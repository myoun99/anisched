import 'dart:async';

import '../models/document.dart';
import 'recovery_snapshots.dart';

// The device's session (files in the app container); the web build makes
// a BrowserDocumentSession (document_session_web.dart) instead. Both
// answer to [DocumentSessionBase], which is what the UI holds.
export 'document_session_io.dart'
    if (dart.library.js_interop) 'document_session_none.dart';

/// What changed, for whoever shows it.
enum DocumentChange {
  /// Binding, dirty flag, recents or the last save error.
  state,

  /// The working database's rows were replaced wholesale (open, reload,
  /// new, restore): every view must read again.
  content,
}

/// The answer of [DocumentSession.resume].
sealed class RemoteCheck {
  const RemoteCheck();
}

/// No document bound (untitled).
final class RemoteUnbound extends RemoteCheck {
  const RemoteUnbound();
}

/// The document is as this device last wrote or read it.
final class RemoteSame extends RemoteCheck {
  const RemoteSame();
}

/// Another device changed it and there were no local edits: reloaded.
final class RemoteReloaded extends RemoteCheck {
  const RemoteReloaded();
}

/// Another device changed it but this device has unsaved edits: the local
/// version stays and will overwrite it (last writer wins). The other
/// version is kept in [snapshot].
final class RemoteKeptLocal extends RemoteCheck {
  const RemoteKeptLocal(this.snapshot);

  final RecoverySnapshot snapshot;
}

/// The document was found empty, or cut short while this device was
/// writing it (the app killed mid-save), and was written again from this
/// device's own copy of its last write.
final class RemoteRepaired extends RemoteCheck {
  const RemoteRepaired();
}

/// The document is gone from its place.
final class RemoteMissing extends RemoteCheck {
  const RemoteMissing();
}

/// The document could not be checked (grant lost, offline, not a document).
final class RemoteUnreachable extends RemoteCheck {
  const RemoteUnreachable(this.error);

  final Object error;
}

/// What the app asks of the session that owns the open document.
abstract interface class DocumentSessionBase {
  /// The bound document, or null while untitled.
  DocumentRef? get document;

  /// The working database has edits the document does not have yet.
  bool get dirty;

  /// Recently opened or saved documents, newest first.
  List<RecentDocument> get recents;

  /// Why the last save failed, cleared by the next successful save.
  Object? get lastSaveError;

  Stream<DocumentChange> get changes;

  /// Whole-document copies to bring back.
  SnapshotShelf get snapshots;

  /// The app is leaving the screen or closing: makes the work safe. Where
  /// the document cannot be replaced atomically (Android) it is NOT
  /// written now — a kill mid-write would leave it cut short — the work
  /// stays in the local database and is saved when the app is back.
  Future<void> flush();

  /// Writes the working database to the bound document when dirty.
  Future<void> save();

  /// Writes to [ref] (a place the user just picked) and binds to it.
  Future<void> saveAs(DocumentRef ref);

  /// Save As where the platform picks the place once the file exists;
  /// false when the user backed out.
  Future<bool> saveAsPlaced(DocumentPlacer place, {required String name});

  /// Opens the document at [ref] into the working database.
  Future<void> openDocument(DocumentRef ref);

  /// Checks the bound document after the app comes back.
  Future<RemoteCheck> resume();

  /// Writes this device's copy of what it last wrote to [ref] back over it
  /// and opens it — for a document found empty or broken
  /// (`NotADocumentKind.empty`). False when there is no such copy.
  Future<bool> restoreLastWritten(DocumentRef ref);

  /// Whether this device keeps a copy of its last write to [ref] — what
  /// [restoreLastWritten] would put back. A quick local check.
  bool hasLastWritten(DocumentRef ref);

  /// Starts a new untitled document (empty catalogue, seeded presets).
  Future<void> startUntitled();

  /// Puts a recovery snapshot's content into the working database.
  Future<void> restoreSnapshot(String snapshotPath);

  /// Drops [ref] from the recent list.
  void forgetRecent(DocumentRef ref);

  /// Stops listening and autosaving. Call [flush] first to save.
  Future<void> close();
}

/// [name] as a document file name: the extension added when missing, path
/// separators taken out.
String documentFileName(String name) {
  final clean = name.replaceAll(RegExp(r'[/\\:]'), '_').trim();
  final base = clean.isEmpty ? 'Untitled' : clean;
  return base.toLowerCase().endsWith('.$documentExtension')
      ? base
      : '$base.$documentExtension';
}

/// Puts the finished document at [stagedPath] (named [fileName]) in its
/// place and answers where it went, or null when the user backed out.
/// It may move the staged file.
typedef DocumentPlacer = Future<DocumentRef?> Function(
  String stagedPath,
  String fileName,
);
