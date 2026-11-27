import 'dart:async';
import 'dart:io';

import '../models/document.dart';

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

/// Real filesystem paths (Windows, Linux, tests).
///
/// The replace writes a temp file beside the document and renames it over,
/// which is atomic on one volume. ⚠️Not for macOS: the sandbox grants the
/// one picked file and nothing beside it — that goes through the
/// coordinator.
class PathDocumentFiles implements DocumentFiles {
  const PathDocumentFiles({this.retries = 3});

  /// Extra rename attempts when a scanner or sync client holds the file for
  /// a moment (Windows).
  final int retries;

  @override
  Future<DocumentRef> reopen(DocumentRef ref) async => ref;

  @override
  Future<DocumentStat?> stat(DocumentRef ref) async {
    final s = await FileStat.stat(ref.location);
    if (s.type == FileSystemEntityType.notFound) return null;
    return (size: s.size, modifiedMs: s.modified.millisecondsSinceEpoch);
  }

  @override
  Future<void> readInto(DocumentRef ref, String localPath) async {
    try {
      await File(ref.location).copy(localPath);
    } on FileSystemException catch (e) {
      throw DocumentUnreachableException(ref, e);
    }
  }

  @override
  Future<void> replaceFrom(String localPath, DocumentRef ref) async {
    final temp = File(
      '${ref.location}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await File(localPath).copy(temp.path);
      for (var attempt = 0; ; attempt++) {
        try {
          await temp.rename(ref.location);
          return;
        } on FileSystemException {
          if (attempt >= retries) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 100 << attempt));
        }
      }
    } on FileSystemException catch (e) {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on FileSystemException {
        // Left for the OS; the document itself is untouched.
      }
      throw DocumentUnreachableException(ref, e);
    }
  }
}
