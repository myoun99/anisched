import 'dart:async';
import 'dart:io';

import '../models/document.dart';
import 'document_files.dart';

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
