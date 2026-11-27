import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/catalogue.dart';
import 'settings_store.dart';

/// Writes to the work catalogue that carry a rule beyond a plain INSERT:
/// default stages, natural sort keys, retake numbering, rate resolution.
class CatalogueStore {
  CatalogueStore(this.db, {this.clock = systemClock})
    : settings = SettingsStore(db);

  final Database db;

  final SettingsStore settings;

  /// Source of "now"; injectable for tests.
  final Clock clock;

  /// Creates a work whose editable stage list is a copy of [presetId]
  /// (the default preset when null). Later preset edits do not touch it.
  int createWork(
    String title, {
    String currency = 'JPY',
    int? clientId,
    int? presetId,
  }) => _transaction(() {
    db.execute(
      'INSERT INTO works (client_id, title, currency, created_at) '
      'VALUES (?, ?, ?, ?);',
      [clientId, title, currency, _now()],
    );
    final workId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO work_stages (work_id, name, position) '
      'SELECT ?, name, position FROM stage_preset_items '
      'WHERE preset_id = ? ORDER BY position;',
      [workId, presetId ?? defaultPresetId()],
    );
    return workId;
  });

  /// The id of the default stage preset.
  int defaultPresetId() =>
      db
              .select('SELECT id FROM stage_presets WHERE is_default = 1;')
              .first['id']
          as int;

  /// The preset's stage names in order.
  List<String> presetStages(int presetId) => [
    for (final r in db.select(
      'SELECT name FROM stage_preset_items WHERE preset_id = ? '
      'ORDER BY position, id;',
      [presetId],
    ))
      r['name'] as String,
  ];

  /// Replaces the preset's stages with [names], in order.
  void setPresetStages(int presetId, List<String> names) => _transaction(() {
    db.execute('DELETE FROM stage_preset_items WHERE preset_id = ?;', [
      presetId,
    ]);
    for (var i = 0; i < names.length; i++) {
      db.execute(
        'INSERT INTO stage_preset_items (preset_id, name, position) '
        'VALUES (?, ?, ?);',
        [presetId, names[i], i],
      );
    }
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

  int addCut(int episodeId, String number, {int? lengthMs, int? partId}) {
    db.execute(
      'INSERT INTO cuts (episode_id, number, sort_key, length_ms, part_id) '
      'VALUES (?, ?, ?, ?, ?);',
      [episodeId, number, naturalSortKey(number), lengthMs, partId],
    );
    return db.lastInsertRowId;
  }

  /// Adds a part (a bundle of the user's cuts) to an episode. The cut
  /// count may be known before the cuts themselves.
  int addPart(int episodeId, String label, {int? plannedCutCount}) {
    db.execute(
      'INSERT INTO parts (episode_id, label, sort_key, planned_cut_count) '
      'VALUES (?, ?, ?, ?);',
      [episodeId, label, naturalSortKey(label), plannedCutCount],
    );
    return db.lastInsertRowId;
  }

  /// Sets the part's deadline for a stage; its cut tasks follow it unless
  /// they carry their own.
  void setPartDue(int partId, int stageId, DateTime dueAt) => db.execute(
    'INSERT INTO part_stage_dues (part_id, stage_id, due_at) VALUES (?, ?, ?) '
    'ON CONFLICT (part_id, stage_id) DO UPDATE SET due_at = excluded.due_at;',
    [partId, stageId, dueAt.toUtc().millisecondsSinceEpoch],
  );

  /// Creates a task for [stageId] on every live cut of the part that does
  /// not have one yet, and returns the new task ids.
  List<int> addTasksForPart(int partId, int stageId) => _transaction(() {
    final cuts = db.select(
      'SELECT c.id FROM cuts c WHERE c.part_id = ? AND c.archived_at IS NULL '
      'AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.cut_id = c.id '
      'AND t.stage_id = ? AND t.archived_at IS NULL) ORDER BY c.sort_key;',
      [partId, stageId],
    );
    return [for (final c in cuts) addTask(stageId, cutId: c['id'] as int)];
  });

  /// The task's deadline: its own, else its part's for the stage.
  ({DateTime? dueAt, bool fromPart}) dueFor(int taskId) {
    final r = db.select(
      'SELECT due_at, from_part FROM task_dues WHERE task_id = ?;',
      [taskId],
    ).first;
    final ms = r['due_at'] as int?;
    return (
      dueAt: ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      fromPart: r['from_part'] == 1,
    );
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
    final base = rate.payFor(
      lengthMs: lengthMs,
      rounding: settings.secondsRounding,
    );
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

  /// Pay for tasks completed in the billing period that closes in
  /// [year]/[month], per currency (no conversion). Each client's own
  /// closing day applies; works without a client close at month end.
  /// `unpriced` counts completed tasks whose pay cannot be computed yet.
  Map<String, ({int total, int unpriced})> monthlyTotals(int year, int month) {
    final closingDays = {
      null,
      for (final r in db.select(
        'SELECT DISTINCT closing_day FROM clients WHERE closing_day IS NOT NULL;',
      ))
        r['closing_day'] as int,
    };
    final totals = <String, ({int total, int unpriced})>{};
    for (final day in closingDays) {
      final p = billingPeriod(year, month, day);
      final rows = db.select(
        '''
SELECT t.id, w.currency FROM tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN clients cl ON cl.id = w.client_id
WHERE t.archived_at IS NULL AND t.done_at >= ? AND t.done_at < ?
  AND cl.closing_day IS ?;''',
        [
          p.start.toUtc().millisecondsSinceEpoch,
          p.end.toUtc().millisecondsSinceEpoch,
          day,
        ],
      );
      for (final r in rows) {
        final currency = r['currency'] as String;
        final pay = payFor(r['id'] as int);
        final prev = totals[currency] ?? (total: 0, unpriced: 0);
        totals[currency] = pay == null
            ? (total: prev.total, unpriced: prev.unpriced + 1)
            : (total: prev.total + pay, unpriced: prev.unpriced);
      }
    }
    return totals;
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
