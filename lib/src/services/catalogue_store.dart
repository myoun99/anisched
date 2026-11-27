import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/catalogue.dart';
import '../models/progress.dart';
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

  /// Every live task of live works with what the views show, in display
  /// order (work, episode, part, stage, cut). One query: rates, lengths,
  /// takes, paid retakes and timer time are resolved in SQL.
  List<TaskRow> taskRows({int? workId}) {
    final now = _now();
    final rounding = settings.secondsRounding;
    final rows = db.select(
      '''
SELECT t.id, t.status, t.received_at, t.due_at AS own_due,
       d.due_at AS part_due,
       t.plan_start_at AS own_plan_start, t.plan_end_at AS own_plan_end,
       pl.start_at AS part_plan_start, pl.end_at AS part_plan_end,
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
LEFT JOIN part_stage_plans pl
  ON pl.part_id = c.part_id AND pl.stage_id = t.stage_id
LEFT JOIN episode_rates r ON r.episode_id = e.id AND r.stage_id = t.stage_id
WHERE t.archived_at IS NULL AND w.archived_at IS NULL
  AND (?2 IS NULL OR w.id = ?2)
ORDER BY w.id, e.sort_key, e.id, p.sort_key, p.id, s.position, s.id,
         c.sort_key, t.id;''',
      [now, workId],
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
  List<PartGroup> partGroups({int? workId}) =>
      groupRows(taskRows(workId: workId));

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
  ({
    List<
      ({
        PartGroup group,
        int? dueInDays,
        Pace? pace,
        bool beforePlan,
        bool planStarted,
      })
    >
    entries,
    int late,
    double cutsToday,
  })
  today({int horizonDays = 4}) {
    final now = clock();
    final dayStart = settings.dayStartMinutes;
    final rest = settings.restWeekdays;
    final paceEnd = settings.paceEnd;
    final off = [for (final d in daysOff(from: now)) d.range];
    int? left(DateTime? due) =>
        due == null ? null : dueInDays(due, now, dayStart);

    final groups = partGroups();
    var late = 0;
    var cutsToday = 0.0;
    final entries =
        <
          ({
            PartGroup group,
            int? dueInDays,
            Pace? pace,
            bool beforePlan,
            bool planStarted,
          })
        >[];
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
      final pace = paceFor(
        g,
        now,
        dayStartMinutes: dayStart,
        restWeekdays: rest,
        daysOff: off,
        endAt: paceEnd,
      );
      if (pace != null) cutsToday += pace.today;
      final due = days != null && days <= horizonDays;
      final active =
          status == TaskStatus.inProgress || status == TaskStatus.retake;
      final toStart = left(g.planStartAt);
      final planStarted = toStart != null && toStart <= 0;
      final beforePlan = toStart != null && toStart > 0;
      if (status.isOpen && (due || active || planStarted)) {
        entries.add((
          group: g,
          dueInDays: days,
          pace: pace,
          beforePlan: beforePlan,
          planStarted: planStarted,
        ));
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
    return (entries: entries, late: late, cutsToday: cutsToday);
  }

  static SecondsRounding _rounding(Object? work, SecondsRounding app) =>
      work == null ? app : SecondsRounding.fromDb(work as String);

  /// Sets or clears one task's own production deadline (a cut's override
  /// of its part's).
  void setTaskDue(int taskId, DateTime? dueAt) => db.execute(
    'UPDATE tasks SET due_at = ? WHERE id = ?;',
    [_ms(dueAt), taskId],
  );

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
