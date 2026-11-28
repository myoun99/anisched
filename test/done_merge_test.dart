import 'package:anisched/src/services/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// v22 (2026-11-28 유저: 완료와 제출 합침): a task left at 'done' is
/// submitted, handed in when it was done.
void main() {
  test('done tasks become submitted with their done time and deadline', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    migrate(db, steps: migrations.where((m) => m.version <= 21).toList());
    const due = 5000;
    for (final sql in [
      "INSERT INTO works (title, currency, created_at) VALUES ('W', 'JPY', 0)",
      "INSERT INTO work_stages (work_id, name, position) VALUES (1, 'LO', 0)",
      "INSERT INTO episodes (work_id, number, sort_key) VALUES (1, '1', '')",
      '''
INSERT INTO cuts (episode_id, number, sort_key) VALUES
  (1, '1', ''), (1, '2', ''), (1, '3', ''), (1, '4', '')''',
      '''
INSERT INTO tasks (id, stage_id, cut_id, status, received_at, due_at,
                   submitted_at, done_at) VALUES
  (1, 1, 1, 'done', 100, $due, NULL, 2000),
  (2, 1, 2, 'done', 300, $due, NULL, NULL),
  (3, 1, 3, 'submitted', 100, $due, 1500, 1500),
  (4, 1, 4, 'in_progress', 100, $due, NULL, 1800)''',
      'INSERT INTO work_intervals (started_at, stopped_at, task_id) VALUES '
          '(1900, NULL, 1)',
    ]) {
      db.execute(sql);
    }

    migrate(db);

    final rows = {
      for (final r in db.select(
        'SELECT id, status, submitted_at, submitted_due_at FROM tasks;',
      ))
        r['id'] as int: (
          r['status'] as String,
          r['submitted_at'] as int?,
          r['submitted_due_at'] as int?,
        ),
    };
    expect(rows, {
      1: ('submitted', 2000, due), // handed in when it was done
      2: ('submitted', 300, due), // no done time: when it came in
      3: ('submitted', 1500, null), // already handed in: untouched
      4: ('in_progress', null, null), // never was done: untouched
    });
    expect(db.select("SELECT 1 FROM tasks WHERE status = 'done'"), isEmpty);
    // A timer on it stops, as at any hand-in.
    expect(
      db.select('SELECT stopped_at FROM work_intervals').single['stopped_at'],
      isNotNull,
    );
  });
}
