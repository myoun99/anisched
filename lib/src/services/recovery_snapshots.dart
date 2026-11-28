// The snapshots themselves are files in the app container (devices);
// the web build keeps none.
export 'recovery_snapshots_io.dart'
    if (dart.library.js_interop) 'recovery_snapshots_web.dart';

/// Why a snapshot was taken.
enum SnapshotReason {
  /// The working copy, just before an open/reload/new replaced it.
  beforeReplace('replaced'),

  /// Another device's version of the document that this device is about
  /// to overwrite (last writer wins).
  overwritten('overwritten');

  const SnapshotReason(this.token);

  final String token;
}

/// One recovery snapshot on disk.
typedef RecoverySnapshot = ({
  String path,
  DateTime takenAt,
  SnapshotReason reason,
  int size,
});

/// The snapshots there are to bring back, newest first.
abstract interface class SnapshotShelf {
  List<RecoverySnapshot> list();
}
