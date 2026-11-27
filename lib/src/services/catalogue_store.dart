import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/catalogue.dart';

/// Writes to the work catalogue that carry a rule beyond a plain INSERT:
/// default stages, natural sort keys, retake numbering, rate resolution.
class CatalogueStore {
  CatalogueStore(this.db, {this.clock = systemClock});

  final Database db;

  /// Source of "now"; injectable for tests.
  final Clock clock;

  /// Creates a work with [defaultStageNames] as its editable stage list.
  int createWork(
    String title, {
    String currency = 'JPY',
    int? clientId,
  }) => _transaction(() {
    db.execute(
      'INSERT INTO works (client_id, title, currency, created_at) '
      'VALUES (?, ?, ?, ?);',
      [clientId, title, currency, _now()],
    );
    final workId = db.lastInsertRowId;
    for (var i = 0; i < defaultStageNames.length; i++) {
      db.execute(
        'INSERT INTO work_stages (work_id, name, position) VALUES (?, ?, ?);',
        [workId, defaultStageNames[i], i],
      );
    }
    return workId;
  });

  /// The work's live stages in order, as (id, name).
  List<({int id, String name})> stages(int workId) => [
    for (final r in db.select(
      'SELECT id, name FROM work_stages '
      'WHERE work_id = ? AND archived_at IS NULL ORDER BY position, id;',
      [workId],
    ))
      (id: r['id'] as int, name: r['name'] as String),
  ];

  int addEpisode(int workId, String number, {String? title}) {
    db.execute(
      'INSERT INTO episodes (work_id, number, sort_key, title) '
      'VALUES (?, ?, ?, ?);',
      [workId, number, naturalSortKey(number), title],
    );
    return db.lastInsertRowId;
  }

  int addCut(int episodeId, String number, {int? lengthMs}) {
    db.execute(
      'INSERT INTO cuts (episode_id, number, sort_key, length_ms) '
      'VALUES (?, ?, ?, ?);',
      [episodeId, number, naturalSortKey(number), lengthMs],
    );
    return db.lastInsertRowId;
  }

  int addStoryboard(int episodeId, String label) {
    db.execute('INSERT INTO storyboards (episode_id, label) VALUES (?, ?);', [
      episodeId,
      label,
    ]);
    return db.lastInsertRowId;
  }

  void setEpisodeRate(int episodeId, int stageId, Rate rate) => db.execute(
    'INSERT INTO episode_rates (episode_id, stage_id, unit, amount) '
    'VALUES (?, ?, ?, ?) ON CONFLICT (episode_id, stage_id) '
    'DO UPDATE SET unit = excluded.unit, amount = excluded.amount;',
    [episodeId, stageId, rate.unit.dbName, rate.amount],
  );

  /// Adds a task for one stage of a cut or a storyboard (exactly one).
  int addTask(
    int stageId, {
    int? cutId,
    int? storyboardId,
    DateTime? dueAt,
    Rate? rate,
  }) {
    db.execute(
      'INSERT INTO tasks (stage_id, cut_id, storyboard_id, received_at, '
      'due_at, rate_unit, rate_amount) VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        stageId,
        cutId,
        storyboardId,
        _now(),
        dueAt?.millisecondsSinceEpoch,
        rate?.unit.dbName,
        rate?.amount,
      ],
    );
    return db.lastInsertRowId;
  }

  void setStatus(int taskId, TaskStatus status) {
    final now = _now();
    final submitted = status == TaskStatus.submitted ? 1 : 0;
    final done = status == TaskStatus.done ? 1 : 0;
    db.execute(
      'UPDATE tasks SET status = ?, '
      'submitted_at = CASE WHEN ? THEN ? ELSE submitted_at END, '
      'done_at = CASE WHEN ? THEN ? ELSE done_at END WHERE id = ?;',
      [status.dbName, submitted, now, done, now, taskId],
    );
  }

  /// Records the next take (2, 3, …) and moves the task to retake.
  /// Free unless [paidAmount] is given.
  int requestRetake(int taskId, {DateTime? dueAt, int? paidAmount}) {
    final paid = paidAmount == null ? 0 : 1;
    return _transaction(() {
      final take =
          db.select(
                'SELECT COALESCE(MAX(take), 1) + 1 AS t FROM retakes '
                'WHERE task_id = ?;',
                [taskId],
              ).first['t']
              as int;
      db.execute(
        'INSERT INTO retakes (task_id, take, received_at, due_at, paid, '
        'amount) VALUES (?, ?, ?, ?, ?, ?);',
        [taskId, take, _now(), dueAt?.millisecondsSinceEpoch, paid, paidAmount],
      );
      db.execute("UPDATE tasks SET status = 'retake' WHERE id = ?;", [taskId]);
      return take;
    });
  }

  /// The task's rate: its own override, else its episode's rate for the
  /// stage, else null.
  Rate? rateFor(int taskId) {
    final rows = db.select(
      '''
SELECT COALESCE(t.rate_unit, r.unit) AS unit,
       COALESCE(t.rate_amount, r.amount) AS amount
FROM tasks t
LEFT JOIN cuts c ON c.id = t.cut_id
LEFT JOIN storyboards s ON s.id = t.storyboard_id
LEFT JOIN episode_rates r
  ON r.stage_id = t.stage_id
 AND r.episode_id = COALESCE(c.episode_id, s.episode_id)
WHERE t.id = ?;''',
      [taskId],
    );
    if (rows.isEmpty || rows.first['unit'] == null) return null;
    return Rate(
      RateUnit.fromDb(rows.first['unit'] as String),
      rows.first['amount'] as int,
    );
  }

  /// Pay for the task itself plus its paid retakes, or null if the rate or
  /// (for per-second rates) the cut length is missing.
  int? payFor(int taskId) {
    final rate = rateFor(taskId);
    if (rate == null) return null;
    final lengthMs =
        db.select(
              'SELECT c.length_ms FROM tasks t '
              'LEFT JOIN cuts c ON c.id = t.cut_id WHERE t.id = ?;',
              [taskId],
            ).first['length_ms']
            as int?;
    final base = rate.payFor(lengthMs: lengthMs);
    if (base == null) return null;
    final extra =
        db.select(
              'SELECT COALESCE(SUM(amount), 0) AS s FROM retakes '
              'WHERE task_id = ? AND paid = 1;',
              [taskId],
            ).first['s']
            as int;
    return base + extra;
  }

  int _now() => clock().toUtc().millisecondsSinceEpoch;

  T _transaction<T>(T Function() body) {
    db.execute('SAVEPOINT catalogue;');
    try {
      final result = body();
      db.execute('RELEASE catalogue;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK TO catalogue;');
      db.execute('RELEASE catalogue;');
      rethrow;
    }
  }
}
