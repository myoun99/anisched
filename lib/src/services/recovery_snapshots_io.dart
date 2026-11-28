import 'dart:io';

import '../core/clock.dart';
import '../models/document.dart';
import 'document_codec.dart';
import 'recovery_snapshots.dart';

/// Whole-document copies kept in the app container (never beside the
/// user's file), so nothing a reload or an overwrite drops is gone for
/// good. Removed after [keepFor] (30 days).
class RecoverySnapshots implements SnapshotShelf {
  RecoverySnapshots(this.folder, {this.clock = systemClock});

  final String folder;
  final Clock clock;

  static const Duration keepFor = Duration(days: 30);

  /// Snapshots the database at [databasePath].
  Future<RecoverySnapshot> takeOf(
    String databasePath,
    SnapshotReason reason,
  ) async {
    final at = clock();
    final path = _pathFor(at, reason);
    final content = await exportDocument(databasePath, path);
    return (path: path, takenAt: at, reason: reason, size: content.size);
  }

  /// Keeps the document file at [documentPath] (already in the app
  /// container) as a snapshot, moving it.
  RecoverySnapshot keep(String documentPath, SnapshotReason reason) {
    final at = clock();
    final path = _pathFor(at, reason);
    final moved = File(documentPath).renameSync(path);
    return (path: path, takenAt: at, reason: reason, size: moved.lengthSync());
  }

  String _pathFor(DateTime at, SnapshotReason reason) {
    Directory(folder).createSync(recursive: true);
    final base =
        '$folder${Platform.pathSeparator}'
        '${at.toUtc().millisecondsSinceEpoch}-${reason.token}';
    var path = '$base.$documentExtension';
    for (var n = 2; File(path).existsSync(); n++) {
      path = '$base-$n.$documentExtension';
    }
    return path;
  }

  /// Every snapshot, newest first.
  @override
  List<RecoverySnapshot> list() {
    final dir = Directory(folder);
    if (!dir.existsSync()) return const [];
    final out = <RecoverySnapshot>[];
    final pattern = RegExp(
      r'^(\d+)-([a-z]+)(?:-\d+)?\.'
      '$documentExtension\$',
    );
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final m = pattern.firstMatch(entity.uri.pathSegments.last);
      if (m == null) continue;
      final reason = SnapshotReason.values
          .where((r) => r.token == m.group(2))
          .firstOrNull;
      if (reason == null) continue;
      out.add((
        path: entity.path,
        takenAt: DateTime.fromMillisecondsSinceEpoch(
          int.parse(m.group(1)!),
          isUtc: true,
        ),
        reason: reason,
        size: entity.lengthSync(),
      ));
    }
    return out..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }

  /// Deletes snapshots older than [keepFor]; answers how many went.
  int collectGarbage() {
    final cutoff = clock().subtract(keepFor);
    var removed = 0;
    for (final s in list()) {
      if (s.takenAt.isBefore(cutoff)) {
        try {
          File(s.path).deleteSync();
          removed++;
        } on FileSystemException {
          // Retried at the next start.
        }
      }
    }
    return removed;
  }
}
