import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/catalogue.dart';
import '../models/cut_numbers.dart';
import '../models/progress.dart';
import '../models/work_interval.dart';
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

  /// Adds many cuts to an episode in one transaction — for example the
  /// numbers from [parseCutNumbers]. Numbers already live in the episode
  /// are skipped and reported, not duplicated.
  ({List<int> added, List<String> skipped}) addCuts(
    int episodeId,
    Iterable<String> numbers, {
    int? partId,
    int? lengthMs,
  }) => _transaction(() {
    final existing = {
      for (final r in db.select(
        'SELECT number FROM cuts WHERE episode_id = ? AND archived_at IS NULL;',
        [episodeId],
      ))
        r['number'] as String,
    };
    final added = <int>[];
    final skipped = <String>[];
    for (final n in numbers) {
      if (!existing.add(n)) {
        skipped.add(n);
        continue;
      }
      added.add(addCut(episodeId, n, lengthMs: lengthMs, partId: partId));
    }
    return (added: added, skipped: skipped);
  });

  /// Puts cuts in a part (or takes them out with null). The part must be
  /// in the cuts' episode.
  void setCutsPart(Iterable<int> cutIds, int? partId) => _transaction(() {
    for (final id in cutIds) {
      db.execute(
        'UPDATE cuts SET part_id = ?1 WHERE id = ?2 AND (?1 IS NULL OR '
        'episode_id = (SELECT episode_id FROM parts WHERE id = ?1));',
        [partId, id],
      );
      if (db.updatedRows != 1) {
        throw ArgumentError('Cut $id is not in the part\'s episode.');
      }
    }
  });

  /// Sets or clears a cut's length (for per-second rates).
  void setCutLength(int cutId, int? lengthMs) => db.execute(
    'UPDATE cuts SET length_ms = ? WHERE id = ?;',
    [lengthMs, cutId],
  );

  void renamePart(int partId, String label) => db.execute(
    'UPDATE parts SET label = ?, sort_key = ? WHERE id = ?;',
    [label, naturalSortKey(label), partId],
  );

  /// Sets or clears how many cuts the part is expected to have.
  void setPlannedCutCount(int partId, int? count) => db.execute(
    'UPDATE parts SET planned_cut_count = ? WHERE id = ?;',
    [count, partId],
  );

  /// Removes the part's deadline for a stage; its cuts keep their own.
  void clearPartDue(int partId, int stageId) => db.execute(
    'DELETE FROM part_stage_dues WHERE part_id = ? AND stage_id = ?;',
    [partId, stageId],
  );

  /// Adds a client; [closingDay] null closes at month end.
  int addClient(String name, {int? closingDay}) {
    db.execute('INSERT INTO clients (name, closing_day) VALUES (?, ?);', [
      name,
      closingDay,
    ]);
    return db.lastInsertRowId;
  }

  List<({int id, String name, int? closingDay})> clients() => [
    for (final r in db.select(
      'SELECT id, name, closing_day FROM clients WHERE archived_at IS NULL '
      'ORDER BY name, id;',
    ))
      (
        id: r['id'] as int,
        name: r['name'] as String,
        closingDay: r['closing_day'] as int?,
      ),
  ];

  /// Live works, newest first.
  List<({int id, String title, String currency, int? clientId})> works() => [
    for (final r in db.select(
      'SELECT id, title, currency, client_id FROM works '
      'WHERE archived_at IS NULL ORDER BY created_at DESC, id DESC;',
    ))
      (
        id: r['id'] as int,
        title: r['title'] as String,
        currency: r['currency'] as String,
        clientId: r['client_id'] as int?,
      ),
  ];

  /// A work's live episodes in number order.
  List<({int id, String number, String? title})> episodes(int workId) => [
    for (final r in db.select(
      'SELECT id, number, title FROM episodes '
      'WHERE work_id = ? AND archived_at IS NULL ORDER BY sort_key, id;',
      [workId],
    ))
      (
        id: r['id'] as int,
        number: r['number'] as String,
        title: r['title'] as String?,
      ),
  ];

  /// An episode's live parts in label order, with their live cut counts.
  List<({int id, String label, int? plannedCutCount, int cutCount})> parts(
    int episodeId,
  ) => [
    for (final r in db.select(
      'SELECT p.id, p.label, p.planned_cut_count, '
      '(SELECT COUNT(*) FROM cuts c WHERE c.part_id = p.id '
      'AND c.archived_at IS NULL) AS cut_count '
      'FROM parts p WHERE p.episode_id = ? AND p.archived_at IS NULL '
      'ORDER BY p.sort_key, p.id;',
      [episodeId],
    ))
      (
        id: r['id'] as int,
        label: r['label'] as String,
        plannedCutCount: r['planned_cut_count'] as int?,
        cutCount: r['cut_count'] as int,
      ),
  ];

  /// An episode's live cuts in number order.
  List<({int id, String number, int? lengthMs, int? partId})> cuts(
    int episodeId,
  ) => [
    for (final r in db.select(
      'SELECT c.id, c.number, c.length_ms, c.part_id FROM cuts c '
      'LEFT JOIN parts p ON p.id = c.part_id '
      'WHERE c.episode_id = ? AND c.archived_at IS NULL '
      'AND (p.id IS NULL OR p.archived_at IS NULL) ORDER BY c.sort_key, c.id;',
      [episodeId],
    ))
      (
        id: r['id'] as int,
        number: r['number'] as String,
        lengthMs: r['length_ms'] as int?,
        partId: r['part_id'] as int?,
      ),
  ];

  /// Timer time per working day for the week holding [weekOf] (today when
  /// null), starting on the week-start setting, days cut at the day-start
  /// setting. A running timer counts up to now.
  List<({DateTime day, Duration worked})> weekHours({DateTime? weekOf}) {
    final now = clock();
    final dayStart = settings.dayStartMinutes;
    final anchor = dayRange(weekOf ?? now, dayStart).start;
    final back = (anchor.weekday - settings.weekStart) % 7;
    final first = DateTime(anchor.year, anchor.month, anchor.day - back);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(first.year, first.month, first.day + i),
    ];
    DateTime startOf(DateTime d) => d.add(Duration(minutes: dayStart));
    final from = startOf(days.first);
    final to = startOf(
      DateTime(days.last.year, days.last.month, days.last.day + 1),
    );
    final spans = _intervals(from, to);
    return [
      for (final d in days)
        (
          day: d,
          worked: totalElapsed(
            spans,
            now.toUtc(),
            from: startOf(d).toUtc(),
            to: startOf(DateTime(d.year, d.month, d.day + 1)).toUtc(),
          ),
        ),
    ];
  }

  /// The timer stretches of the working day holding [day] (today when
  /// null), clipped to it, oldest first, with the work they were on.
  List<({DateTime start, DateTime end, bool running, int? workId, int? taskId})>
  dayIntervals({DateTime? day}) {
    final now = clock().toUtc();
    final range = dayRange(day ?? clock(), settings.dayStartMinutes);
    final from = range.start.toUtc();
    final to = range.end.toUtc();
    final rows = db.select(
      '''
SELECT i.started_at, i.stopped_at, i.task_id, s.work_id
FROM work_intervals i
LEFT JOIN tasks t ON t.id = i.task_id
LEFT JOIN work_stages s ON s.id = t.stage_id
WHERE i.started_at < ? AND (i.stopped_at IS NULL OR i.stopped_at > ?)
ORDER BY i.started_at;''',
      [_ms(to), _ms(from)],
    );
    DateTime utc(int ms) =>
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return [
      for (final r in rows)
        if (_clip(
              utc(r['started_at'] as int),
              r['stopped_at'] == null ? now : utc(r['stopped_at'] as int),
              from,
              to,
            )
            case (final s, final e))
          (
            start: s,
            end: e,
            running: r['stopped_at'] == null,
            workId: r['work_id'] as int?,
            taskId: r['task_id'] as int?,
          ),
    ];
  }

  static (DateTime, DateTime)? _clip(
    DateTime s,
    DateTime e,
    DateTime from,
    DateTime to,
  ) {
    final a = s.isAfter(from) ? s : from;
    final b = e.isBefore(to) ? e : to;
    return b.isAfter(a) ? (a, b) : null;
  }

  List<WorkInterval> _intervals(DateTime from, DateTime to) => [
    for (final r in db.select(
      'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
      'WHERE started_at < ? AND (stopped_at IS NULL OR stopped_at > ?);',
      [_ms(to), _ms(from)],
    ))
      WorkInterval(
        id: r['id'] as int,
        start: DateTime.fromMillisecondsSinceEpoch(
          r['started_at'] as int,
          isUtc: true,
        ),
        stop: r['stopped_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                r['stopped_at'] as int,
                isUtc: true,
              ),
        taskId: r['task_id'] as int?,
      ),
  ];

  /// Hides [id] of [kind] and everything beneath it from the views. The
  /// rows stay; [restore] brings them back.
  void archive(ArchiveKind kind, int id) {
    db.execute(
      'UPDATE ${kind.table} SET archived_at = ? '
      'WHERE id = ? AND archived_at IS NULL;',
      [_now(), id],
    );
  }

  /// Brings back an archived item. Throws [StateError] when a live item
  /// now takes its place (a cut number or a cut × stage reused since).
  void restore(ArchiveKind kind, int id) {
    try {
      db.execute('UPDATE ${kind.table} SET archived_at = NULL WHERE id = ?;', [
        id,
      ]);
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067 || e.resultCode == 19) {
        throw StateError(
          'Cannot restore ${kind.name} $id: a live one now uses its place.',
        );
      }
      rethrow;
    }
  }

  /// Archived items, newest first, with a label to show: works by title,
  /// episodes by number, parts by label, cuts by number, storyboards by
  /// label, tasks by "cut or storyboard · stage", stages by name.
  List<({ArchiveKind kind, int id, String label, DateTime archivedAt})>
  archived() {
    final rows = db.select('''
SELECT 'work' AS kind, id, title AS label, archived_at FROM works
  WHERE archived_at IS NOT NULL
UNION ALL SELECT 'episode', e.id, w.title || ' ' || e.number, e.archived_at
  FROM episodes e JOIN works w ON w.id = e.work_id
  WHERE e.archived_at IS NOT NULL
UNION ALL SELECT 'part', p.id, e.number || ' ' || p.label, p.archived_at
  FROM parts p JOIN episodes e ON e.id = p.episode_id
  WHERE p.archived_at IS NOT NULL
UNION ALL SELECT 'cut', c.id, e.number || ' ' || c.number, c.archived_at
  FROM cuts c JOIN episodes e ON e.id = c.episode_id
  WHERE c.archived_at IS NOT NULL
UNION ALL SELECT 'storyboard', sb.id, e.number || ' ' || sb.label,
    sb.archived_at
  FROM storyboards sb JOIN episodes e ON e.id = sb.episode_id
  WHERE sb.archived_at IS NOT NULL
UNION ALL SELECT 'task', t.id,
    COALESCE(c.number, sb.label) || ' · ' || s.name, t.archived_at
  FROM tasks t JOIN work_stages s ON s.id = t.stage_id
  LEFT JOIN cuts c ON c.id = t.cut_id
  LEFT JOIN storyboards sb ON sb.id = t.storyboard_id
  WHERE t.archived_at IS NOT NULL
UNION ALL SELECT 'stage', s.id, w.title || ' · ' || s.name, s.archived_at
  FROM work_stages s JOIN works w ON w.id = s.work_id
  WHERE s.archived_at IS NOT NULL
ORDER BY 4 DESC, 1, 2;''');
    return [
      for (final r in rows)
        (
          kind: ArchiveKind.values.byName(r['kind'] as String),
          id: r['id'] as int,
          label: r['label'] as String,
          archivedAt: DateTime.fromMillisecondsSinceEpoch(
            r['archived_at'] as int,
            isUtc: true,
          ),
        ),
    ];
  }

  /// Adds a stage to a work's own list, at the end or before
  /// [beforeStageId], and returns its id. Presets are not touched.
  int addStage(int workId, String name, {int? beforeStageId}) =>
      _transaction(() {
        final ids = [for (final s in stages(workId)) s.id];
        var at = ids.length;
        if (beforeStageId != null) {
          at = ids.indexOf(beforeStageId);
          if (at < 0) {
            throw ArgumentError.value(beforeStageId, 'beforeStageId');
          }
        }
        db.execute(
          'INSERT INTO work_stages (work_id, name, position) VALUES (?, ?, 0);',
          [workId, name],
        );
        final id = db.lastInsertRowId;
        _setOrder([...ids.take(at), id, ...ids.skip(at)]);
        return id;
      });

  void renameStage(int stageId, String name) => db.execute(
    'UPDATE work_stages SET name = ? WHERE id = ?;',
    [name, stageId],
  );

  /// Puts a work's live stages in the order of [stageIds], which must be
  /// exactly those stages.
  void reorderStages(int workId, List<int> stageIds) => _transaction(() {
    final live = {for (final s in stages(workId)) s.id};
    if (stageIds.length != live.length || !live.containsAll(stageIds)) {
      throw ArgumentError('Give every live stage of the work exactly once.');
    }
    _setOrder(stageIds);
  });

  void _setOrder(List<int> stageIds) {
    for (var i = 0; i < stageIds.length; i++) {
      db.execute('UPDATE work_stages SET position = ? WHERE id = ?;', [
        i,
        stageIds[i],
      ]);
    }
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
    final row = db.select(
      'SELECT c.length_ms, w.seconds_rounding FROM tasks t '
      'LEFT JOIN cuts c ON c.id = t.cut_id '
      'JOIN work_stages s ON s.id = t.stage_id '
      'JOIN works w ON w.id = s.work_id WHERE t.id = ?;',
      [taskId],
    ).first;
    final base = rate.payFor(
      lengthMs: row['length_ms'] as int?,
      rounding: _rounding(row['seconds_rounding'], settings.secondsRounding),
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
SELECT t.id, w.currency FROM live_tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN clients cl ON cl.id = w.client_id
WHERE t.done_at >= ? AND t.done_at < ?
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

  /// Every live task of live works with what the views show, in display
  /// order (work, episode, part, stage, cut). One query: rates, lengths,
  /// takes, paid retakes and timer time are resolved in SQL.
  ///
  /// Unless [includeDone], a done task is left out when every task of its
  /// group is done too — finished units drop off the views, while a done
  /// cut still counts in a part that has open ones ("3/6").
  List<TaskRow> taskRows({int? workId, bool includeDone = false}) {
    final now = _now();
    final rounding = settings.secondsRounding;
    final rows = db.select(
      '''
SELECT t.id, t.status, t.received_at, t.due_at AS own_due,
       d.due_at AS part_due,
       t.plan_start_at AS own_plan_start, t.plan_end_at AS own_plan_end,
       pl.start_at AS part_plan_start, pl.end_at AS part_plan_end,
       t.kickoff_at AS own_kickoff, k.kickoff_at AS part_kickoff,
       s.id AS stage_id, s.name AS stage_name,
       w.id AS work_id, w.title, w.currency, w.seconds_rounding,
       e.id AS episode_id, e.number AS episode_number,
       c.id AS cut_id, c.number AS cut_number, c.length_ms,
       sb.id AS storyboard_id, sb.label AS storyboard_label,
       p.id AS part_id, p.label AS part_label, p.planned_cut_count,
       COALESCE(t.rate_unit, r.unit) AS unit,
       COALESCE(t.rate_amount, r.amount) AS amount,
       (SELECT COALESCE(MAX(take), 1) FROM retakes WHERE task_id = t.id)
         AS take,
       (SELECT COALESCE(SUM(amount), 0) FROM retakes
         WHERE task_id = t.id AND paid = 1) AS extra,
       (SELECT COALESCE(SUM(MAX(COALESCE(stopped_at, ?1) - started_at, 0)), 0)
         FROM work_intervals WHERE task_id = t.id) AS worked_ms
FROM tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN cuts c ON c.id = t.cut_id
LEFT JOIN storyboards sb ON sb.id = t.storyboard_id
JOIN episodes e ON e.id = COALESCE(c.episode_id, sb.episode_id)
LEFT JOIN parts p ON p.id = c.part_id
LEFT JOIN part_stage_dues d
  ON d.part_id = c.part_id AND d.stage_id = t.stage_id
LEFT JOIN part_stage_kickoffs k
  ON k.part_id = c.part_id AND k.stage_id = t.stage_id
LEFT JOIN part_stage_plans pl
  ON pl.part_id = c.part_id AND pl.stage_id = t.stage_id
LEFT JOIN episode_rates r ON r.episode_id = e.id AND r.stage_id = t.stage_id
WHERE (?2 IS NULL OR w.id = ?2)
  -- the live_tasks conditions, inlined: these joins are already here
  AND t.archived_at IS NULL AND w.archived_at IS NULL
  AND e.archived_at IS NULL
  AND (c.id IS NULL OR c.archived_at IS NULL)
  AND (sb.id IS NULL OR sb.archived_at IS NULL)
  AND (p.id IS NULL OR p.archived_at IS NULL)
  AND (?3 = 1 OR t.status <> 'done' OR (t.storyboard_id IS NULL AND EXISTS (
    SELECT 1 FROM cuts c2 JOIN live_tasks t2 ON t2.cut_id = c2.id
    WHERE t2.stage_id = t.stage_id AND t2.status <> 'done'
      AND (c2.part_id = c.part_id
        OR (c.part_id IS NULL AND c2.part_id IS NULL
            AND c2.episode_id = c.episode_id)))))
ORDER BY w.id, e.sort_key, e.id, p.sort_key, p.id, s.position, s.id,
         c.sort_key, t.id;''',
      [now, workId, if (includeDone) 1 else 0],
    );
    DateTime? utc(Object? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);
    return [
      for (final r in rows)
        TaskRow(
          id: r['id'] as int,
          status: TaskStatus.fromDb(r['status'] as String),
          take: r['take'] as int,
          workId: r['work_id'] as int,
          workTitle: r['title'] as String,
          currency: r['currency'] as String,
          episodeId: r['episode_id'] as int,
          episodeNumber: r['episode_number'] as String,
          stageId: r['stage_id'] as int,
          stageName: r['stage_name'] as String,
          cutId: r['cut_id'] as int?,
          cutNumber: r['cut_number'] as String?,
          lengthMs: r['length_ms'] as int?,
          storyboardId: r['storyboard_id'] as int?,
          storyboardLabel: r['storyboard_label'] as String?,
          partId: r['part_id'] as int?,
          partLabel: r['part_label'] as String?,
          plannedCutCount: r['planned_cut_count'] as int?,
          receivedAt: utc(r['received_at']),
          ownDueAt: utc(r['own_due']),
          partDueAt: utc(r['part_due']),
          ownPlanStartAt: utc(r['own_plan_start']),
          ownPlanEndAt: utc(r['own_plan_end']),
          partPlanStartAt: utc(r['part_plan_start']),
          partPlanEndAt: utc(r['part_plan_end']),
          ownKickoffAt: utc(r['own_kickoff']),
          partKickoffAt: utc(r['part_kickoff']),
          pay: _pay(
            r['unit'] as String?,
            r['amount'] as int?,
            r['length_ms'] as int?,
            r['extra'] as int,
            _rounding(r['seconds_rounding'], rounding),
          ),
          worked: Duration(milliseconds: r['worked_ms'] as int),
        ),
    ];
  }

  /// Schedule units — part × stage, part-less cuts of an episode × stage,
  /// or a storyboard task alone — with progress, status, pay and time,
  /// sorted by deadline (none last). Two queries in all, whatever the row
  /// count: the settings read and [taskRows].
  /// Finished units are left out unless [includeDone].
  List<PartGroup> partGroups({int? workId, bool includeDone = false}) =>
      groupRows(
        taskRows(workId: workId, includeDone: includeDone),
        manualOrder: {
          for (final r in db.select(
            'SELECT group_key, position FROM group_order;',
          ))
            r['group_key'] as String: r['position'] as int,
        },
      );

  /// Saves the user's drag order: [groupKeys] (from [PartGroup.key]) in
  /// display order, replacing any earlier order. Units not listed fall
  /// after the listed ones, by deadline.
  void setGroupOrder(List<String> groupKeys) => _transaction(() {
    db.execute('DELETE FROM group_order;');
    for (var i = 0; i < groupKeys.length; i++) {
      db.execute(
        'INSERT OR IGNORE INTO group_order (group_key, position) VALUES (?, ?);',
        [groupKeys[i], i],
      );
    }
  });

  /// "Sort automatically": drops the drag order, back to deadline order.
  void clearGroupOrder() => db.execute('DELETE FROM group_order;');

  /// True when a drag order is saved.
  bool get hasGroupOrder =>
      db.select('SELECT 1 FROM group_order LIMIT 1;').isNotEmpty;

  /// The pace (cuts per working day) for [group] as of now, using the
  /// day start, rest weekdays and pace-end settings.
  Pace? paceOf(PartGroup group) => paceFor(
    group,
    clock(),
    dayStartMinutes: settings.dayStartMinutes,
    restWeekdays: settings.restWeekdays,
    daysOff: daysOff().map((d) => d.range),
    endAt: settings.paceEnd,
  );

  /// The usual pace per stage name: cuts handed over (submitted, or done
  /// without a submission) in the last [days] days up to today, divided
  /// by the working days in that window. Stages of every work with the
  /// same name pool together ("LO" in two works is one LO speed).
  List<UsualPace> usualPaces({int? days}) {
    days ??= settings.recentPaceDays;
    final now = clock();
    final today = dayRange(now, settings.dayStartMinutes);
    final from = DateTime(
      today.start.year,
      today.start.month,
      today.start.day - (days - 1),
    ).add(Duration(minutes: settings.dayStartMinutes));
    final workDays = workDaysBetween(
      from,
      today.start,
      restWeekdays: settings.restWeekdays,
      daysOff: daysOff(from: from).map((d) => d.range),
    );
    return [
      for (final r in db.select(
        '''
SELECT s.name AS stage_name, COUNT(*) AS cuts
FROM live_tasks t JOIN work_stages s ON s.id = t.stage_id
WHERE 1
  AND COALESCE(t.submitted_at, t.done_at) >= ?
  AND COALESCE(t.submitted_at, t.done_at) < ?
GROUP BY s.name ORDER BY s.name;''',
        [_ms(from), _ms(today.end)],
      ))
        UsualPace(
          stageName: r['stage_name'] as String,
          cuts: r['cuts'] as int,
          workDays: workDays,
        ),
    ];
  }

  /// Each stage name's recent average (the last
  /// [SettingsStore.recentPaceDays] days) and overall average (from its
  /// first handed-over cut to today), both in cuts per working day.
  List<StagePace> stagePaces() {
    final recent = {for (final u in usualPaces()) u.stageName: u};
    final now = clock();
    final today = dayRange(now, settings.dayStartMinutes);
    final rest = settings.restWeekdays;
    final off = [for (final d in daysOff()) d.range];
    final overall = <String, UsualPace>{};
    for (final r in db.select(
      '''
SELECT s.name AS stage_name, COUNT(*) AS cuts,
       MIN(COALESCE(t.submitted_at, t.done_at)) AS first_at
FROM live_tasks t JOIN work_stages s ON s.id = t.stage_id
WHERE 1
  AND COALESCE(t.submitted_at, t.done_at) IS NOT NULL
  AND COALESCE(t.submitted_at, t.done_at) < ?
GROUP BY s.name;''',
      [_ms(today.end)],
    )) {
      final first = dayRange(
        DateTime.fromMillisecondsSinceEpoch(r['first_at'] as int),
        settings.dayStartMinutes,
      ).start;
      final name = r['stage_name'] as String;
      overall[name] = UsualPace(
        stageName: name,
        cuts: r['cuts'] as int,
        workDays: workDaysBetween(
          first,
          today.start,
          restWeekdays: rest,
          daysOff: off,
        ),
      );
    }
    return [
      for (final name in {...overall.keys, ...recent.keys}.toList()..sort())
        StagePace(
          stageName: name,
          recent:
              recent[name] ??
              UsualPace(
                stageName: name,
                cuts: 0,
                workDays: recent.values.firstOrNull?.workDays ?? 0,
              ),
          overall:
              overall[name] ?? UsualPace(stageName: name, cuts: 0, workDays: 0),
        ),
    ];
  }

  /// Recent cuts per working day by stage name (null without working
  /// days), the speed the plan signal compares against.
  Map<String, double?> recentPerDay() => {
    for (final u in usualPaces()) u.stageName: u.perDay,
  };

  /// The deadline and plan signals and needed pace of every group in
  /// [partGroups], by group key.
  Map<String, GroupSignals> signals({bool includeDone = false}) {
    final now = clock();
    final dayStart = settings.dayStartMinutes;
    final rest = settings.restWeekdays;
    final off = [for (final d in daysOff(from: now)) d.range];
    final paceEnd = settings.paceEnd;
    final recent = recentPerDay();
    return {
      for (final g in partGroups(includeDone: includeDone))
        g.key: _signals(g, now, dayStart, rest, off, paceEnd, recent),
    };
  }

  static GroupSignals _signals(
    PartGroup g,
    DateTime now,
    int dayStart,
    Set<int> rest,
    List<DaysOff> off,
    PaceEnd paceEnd,
    Map<String, double?> recent,
  ) {
    final pace = paceFor(
      g,
      now,
      dayStartMinutes: dayStart,
      restWeekdays: rest,
      daysOff: off,
      endAt: paceEnd,
    );
    return GroupSignals(
      due: dueSignal(g, now: now, dayStartMinutes: dayStart),
      plan: planSignal(
        g,
        now: now,
        dayStartMinutes: dayStart,
        pace: pace,
        recentPerDay: recent[g.stageName],
      ),
      pace: pace,
    );
  }

  /// Adds days off from [start] to [end] (one day when null), by their
  /// local calendar dates, and returns the id.
  int addDaysOff(DateTime start, {DateTime? end, String? note}) {
    final r = DaysOff(start, end);
    db.execute(
      'INSERT INTO days_off (start_date, end_date, note) VALUES (?, ?, ?);',
      [_isoDate(r.start), _isoDate(r.end), note],
    );
    return db.lastInsertRowId;
  }

  void removeDaysOff(int id) =>
      db.execute('DELETE FROM days_off WHERE id = ?;', [id]);

  /// Days off ending on or after [from] (all when null), earliest first.
  List<({int id, DaysOff range, String? note})> daysOff({DateTime? from}) => [
    for (final r in db.select(
      'SELECT id, start_date, end_date, note FROM days_off '
      'WHERE ? IS NULL OR end_date >= ? ORDER BY start_date, id;',
      [
        if (from == null) null else _isoDate(from),
        if (from == null) null else _isoDate(from),
      ],
    ))
      (
        id: r['id'] as int,
        range: DaysOff(
          DateTime.parse(r['start_date'] as String),
          DateTime.parse(r['end_date'] as String),
        ),
        note: r['note'] as String?,
      ),
  ];

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The "today" list: open groups that are due within [horizonDays] days
  /// (or late), in progress or in retake, or whose planned start has come.
  /// Nothing is hidden for a later planned start — such entries carry
  /// `beforePlan` so the view can dim them ("starts 12/7").
  /// Sorted by days left (no deadline last), then urgency.
  /// Each entry carries its [Pace]. `late` counts late open groups plus
  /// late open cuts whose own deadline overrides their part's.
  /// `cutsToday` sums what every open group asks of today — not only the
  /// listed ones — so overlapping parts add up.
  TodayView today({int horizonDays = 4}) {
    final now = clock();
    final dayStart = settings.dayStartMinutes;
    final rest = settings.restWeekdays;
    final paceEnd = settings.paceEnd;
    final off = [for (final d in daysOff(from: now)) d.range];
    final recent = recentPerDay();
    int? left(DateTime? due) =>
        due == null ? null : dueInDays(due, now, dayStart);

    final groups = partGroups();
    var late = 0;
    var cutsToday = 0.0;
    final entries = <TodayEntry>[];
    for (final g in groups) {
      final status = g.status;
      final days = left(g.dueAt);
      if (status.isOpen && days != null && days < 0) late++;
      for (final t in g.tasks) {
        if (t.dueOverridden && t.isOpen) {
          final d = left(t.ownDueAt);
          if (d != null && d < 0) late++;
        }
      }
      final sig = _signals(g, now, dayStart, rest, off, paceEnd, recent);
      final pace = sig.pace;
      if (pace != null) cutsToday += pace.today;
      final due = days != null && days <= horizonDays;
      final active =
          status == TaskStatus.inProgress || status == TaskStatus.retake;
      final toStart = left(g.planStartAt);
      final planStarted = toStart != null && toStart <= 0;
      final beforePlan = toStart != null && toStart > 0;
      if (status.isOpen && (due || active || planStarted)) {
        entries.add(
          TodayEntry(
            group: g,
            dueInDays: days,
            pace: pace,
            beforePlan: beforePlan,
            planStarted: planStarted,
            due: sig.due,
            plan: sig.plan,
          ),
        );
      }
    }
    entries.sort((a, b) {
      final da = a.dueInDays;
      final dbb = b.dueInDays;
      if (da != dbb) {
        if (da == null) return 1;
        if (dbb == null) return -1;
        return da.compareTo(dbb);
      }
      return a.group.status.urgency.compareTo(b.group.status.urgency);
    });
    return TodayView(entries: entries, late: late, cutsToday: cutsToday);
  }

  static SecondsRounding _rounding(Object? work, SecondsRounding app) =>
      work == null ? app : SecondsRounding.fromDb(work as String);

  /// Sets or clears one task's own production deadline (a cut's override
  /// of its part's).
  void setTaskDue(int taskId, DateTime? dueAt) => db.execute(
    'UPDATE tasks SET due_at = ? WHERE id = ?;',
    [_ms(dueAt), taskId],
  );

  /// Sets or clears (null) when production work began for a part × stage.
  void setPartKickoff(int partId, int stageId, DateTime? kickoffAt) {
    if (kickoffAt == null) {
      db.execute(
        'DELETE FROM part_stage_kickoffs WHERE part_id = ? AND stage_id = ?;',
        [partId, stageId],
      );
      return;
    }
    db.execute(
      'INSERT INTO part_stage_kickoffs (part_id, stage_id, kickoff_at) '
      'VALUES (?, ?, ?) ON CONFLICT (part_id, stage_id) '
      'DO UPDATE SET kickoff_at = excluded.kickoff_at;',
      [partId, stageId, _ms(kickoffAt)],
    );
  }

  /// Sets or clears one task's own kickoff (a cut's override).
  void setTaskKickoff(int taskId, DateTime? kickoffAt) => db.execute(
    'UPDATE tasks SET kickoff_at = ? WHERE id = ?;',
    [_ms(kickoffAt), taskId],
  );

  /// Writes a part × stage's production schedule — kickoff and deadline —
  /// in one transaction, as a timeline bar dropped after a drag. A null
  /// clears that end.
  void setPartSchedule(
    int partId,
    int stageId, {
    required DateTime? kickoffAt,
    required DateTime? dueAt,
  }) => _transaction(() {
    if (kickoffAt != null && dueAt != null && dueAt.isBefore(kickoffAt)) {
      throw ArgumentError('A deadline cannot come before the kickoff.');
    }
    setPartKickoff(partId, stageId, kickoffAt);
    if (dueAt == null) {
      clearPartDue(partId, stageId);
    } else {
      setPartDue(partId, stageId, dueAt);
    }
  });

  /// Sets the user's own plan for a part × stage. Both null removes it.
  void setPartPlan(int partId, int stageId, {DateTime? start, DateTime? end}) {
    if (start == null && end == null) {
      db.execute(
        'DELETE FROM part_stage_plans WHERE part_id = ? AND stage_id = ?;',
        [partId, stageId],
      );
      return;
    }
    db.execute(
      'INSERT INTO part_stage_plans (part_id, stage_id, start_at, end_at) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (part_id, stage_id) '
      'DO UPDATE SET start_at = excluded.start_at, end_at = excluded.end_at;',
      [partId, stageId, _ms(start), _ms(end)],
    );
  }

  /// Sets one task's own plan; a null end follows the part's.
  void setTaskPlan(int taskId, {DateTime? start, DateTime? end}) {
    if (start != null && end != null && end.isBefore(start)) {
      throw ArgumentError('A plan cannot end before it starts.');
    }
    db.execute(
      'UPDATE tasks SET plan_start_at = ?, plan_end_at = ? WHERE id = ?;',
      [_ms(start), _ms(end), taskId],
    );
  }

  /// The rate unit preselected when entering this work's rates.
  RateUnit workDefaultRateUnit(int workId) => RateUnit.fromDb(
    db.select('SELECT default_rate_unit FROM works WHERE id = ?;', [
          workId,
        ]).first['default_rate_unit']
        as String,
  );

  void setWorkDefaultRateUnit(int workId, RateUnit unit) => db.execute(
    'UPDATE works SET default_rate_unit = ? WHERE id = ?;',
    [unit.dbName, workId],
  );

  static int? _ms(DateTime? t) => t?.toUtc().millisecondsSinceEpoch;

  /// Gives one task (one stage of one cut) its own rate; null goes back to
  /// the episode's rate for the stage.
  void setTaskRate(int taskId, Rate? rate) => db.execute(
    'UPDATE tasks SET rate_unit = ?, rate_amount = ? WHERE id = ?;',
    [rate?.unit.dbName, rate?.amount, taskId],
  );

  /// Sets the work's own seconds rounding; null follows the app setting.
  void setWorkRounding(int workId, SecondsRounding? rounding) => db.execute(
    'UPDATE works SET seconds_rounding = ? WHERE id = ?;',
    [rounding?.dbName, workId],
  );

  /// Moves every task in [taskIds] to [status] in one transaction, with
  /// the same timestamps a single [setStatus] would set.
  void setStatusMany(Iterable<int> taskIds, TaskStatus status) =>
      _transaction(() {
        for (final id in taskIds) {
          setStatus(id, status);
        }
      });

  /// Stage presets as (id, name, isDefault), default first, then by name.
  List<({int id, String name, bool isDefault})> presets() => [
    for (final r in db.select(
      'SELECT id, name, is_default FROM stage_presets '
      'ORDER BY is_default DESC, name, id;',
    ))
      (
        id: r['id'] as int,
        name: r['name'] as String,
        isDefault: r['is_default'] == 1,
      ),
  ];

  /// Adds a preset with [stages] in order, and returns its id.
  int createPreset(String name, List<String> stages) => _transaction(() {
    db.execute('INSERT INTO stage_presets (name) VALUES (?);', [name]);
    final id = db.lastInsertRowId;
    setPresetStages(id, stages);
    return id;
  });

  void renamePreset(int presetId, String name) => db.execute(
    'UPDATE stage_presets SET name = ? WHERE id = ?;',
    [name, presetId],
  );

  /// Makes [presetId] the one preset new works use when none is chosen.
  void setDefaultPreset(int presetId) => _transaction(() {
    db
      ..execute('UPDATE stage_presets SET is_default = 0 WHERE is_default = 1;')
      ..execute('UPDATE stage_presets SET is_default = 1 WHERE id = ?;', [
        presetId,
      ]);
    if (db.updatedRows != 1) {
      throw ArgumentError.value(presetId, 'presetId', 'no such preset');
    }
  });

  /// Deletes a preset. Works made from it keep their stages. The default
  /// preset cannot be deleted; make another the default first.
  void deletePreset(int presetId) => _transaction(() {
    final rows = db.select(
      'SELECT is_default FROM stage_presets WHERE id = ?;',
      [presetId],
    );
    if (rows.isEmpty) return;
    if (rows.first['is_default'] == 1) {
      throw StateError('The default stage preset cannot be deleted.');
    }
    db
      ..execute('DELETE FROM stage_preset_items WHERE preset_id = ?;', [
        presetId,
      ])
      ..execute('DELETE FROM stage_presets WHERE id = ?;', [presetId]);
  });

  static int? _pay(
    String? unit,
    int? amount,
    int? lengthMs,
    int extra,
    SecondsRounding rounding,
  ) {
    if (unit == null || amount == null) return null;
    final base = Rate(
      RateUnit.fromDb(unit),
      amount,
    ).payFor(lengthMs: lengthMs, rounding: rounding);
    return base == null ? null : base + extra;
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
