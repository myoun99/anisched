import 'recovery_snapshots.dart';

/// The web build keeps no snapshots: the working database lives in the
/// browser, and a document comes in or goes out as a whole file.
class NoSnapshots implements SnapshotShelf {
  const NoSnapshots();

  @override
  List<RecoverySnapshot> list() => const [];
}
