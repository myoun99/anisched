import 'package:sqlite3/sqlite3.dart';

/// One forward-only schema step. [version] is the `user_version` the
/// database has after [apply] runs.
class Migration {
  const Migration(this.version, this.apply);

  final int version;
  final void Function(Database db) apply;
}

/// Every migration, oldest first. Append only — never edit a shipped step;
/// a fix is a new step. Versions must be 1, 2, 3, … with no gaps.
///
/// v1 holds only what does not depend on open domain questions: timer
/// intervals. Works, episodes, cuts, rates and invoices arrive as later
/// steps once their rules are settled.
final List<Migration> migrations = [
  Migration(1, (db) {
    db.execute('''
CREATE TABLE work_intervals (
  id INTEGER PRIMARY KEY,
  started_at INTEGER NOT NULL,
  stopped_at INTEGER,
  CHECK (stopped_at IS NULL OR stopped_at >= started_at)
);''');
    db.execute(
      'CREATE INDEX work_intervals_started ON work_intervals(started_at);',
    );
  }),
];

/// The schema version this build expects.
int get latestSchemaVersion => migrations.isEmpty ? 0 : migrations.last.version;

/// Thrown when the file was written by a newer build than this one.
class SchemaTooNewException implements Exception {
  SchemaTooNewException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'Database schema v$found is newer than this build supports (v$supported).';
}

/// Brings [db] up to the latest version. Each step runs in its own
/// transaction together with its `user_version` bump, so a crash mid-way
/// leaves the file at the last completed version, never half-migrated.
void migrate(Database db, {List<Migration>? steps}) {
  final all = steps ?? migrations;
  final target = all.isEmpty ? 0 : all.last.version;
  final current = db.userVersion;
  if (current > target) throw SchemaTooNewException(current, target);
  for (var i = 0; i < all.length; i++) {
    final step = all[i];
    if (step.version != i + 1) {
      throw StateError('Migration versions must be contiguous from 1.');
    }
    if (step.version <= current) continue;
    db.execute('BEGIN IMMEDIATE;');
    try {
      step.apply(db);
      db.userVersion = step.version;
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }
}
