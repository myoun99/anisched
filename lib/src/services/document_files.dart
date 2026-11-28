import 'dart:async';

import '../models/document.dart';

// Real paths (devices); the web build has none.
export 'document_files_io.dart'
    if (dart.library.js_interop) 'document_files_web.dart';

/// The three things the app ever does to a document file — and nothing
/// else: ask about it, copy it in whole, replace it whole.
///
/// Every platform's rules live behind this. The working database never
/// touches the document directly (docs/storage.md):
/// - Windows/Linux: real paths ([PathDocumentFiles]).
/// - iOS/macOS: security-scoped bookmark + NSFileCoordinator (coordinated
///   read, `.forReplacing` write) — native, to come.
/// - Android: SAF `content://` URI with a persistable permission, read and
///   written as streams — native, to come.
abstract interface class DocumentFiles {
  /// Re-establishes access after a relaunch (resolve a bookmark, refresh a
  /// stale one) and answers the ref to use from now on. Throws
  /// [DocumentUnreachableException] when the grant is gone.
  Future<DocumentRef> reopen(DocumentRef ref);

  /// Size and modification time, or null when the document is not there.
  Future<DocumentStat?> stat(DocumentRef ref);

  /// Copies the whole document to [localPath] (a file in the app
  /// container). On Apple this is the coordinated read that makes a file
  /// provider hand over its current version.
  Future<void> readInto(DocumentRef ref, String localPath);

  /// Replaces the whole document with [localPath]'s bytes so a reader never
  /// sees half a file.
  Future<void> replaceFrom(String localPath, DocumentRef ref);
}

/// The document could not be reached: the grant is gone, the provider
/// refused, the volume is offline.
class DocumentUnreachableException implements Exception {
  DocumentUnreachableException(this.ref, this.reason);

  final DocumentRef ref;
  final Object reason;

  @override
  String toString() => 'DocumentUnreachableException(${ref.location}: $reason)';
}
