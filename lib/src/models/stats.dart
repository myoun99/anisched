/// The statistics tab's numbers (docs/data-model.md, 통계).
///
/// Pure: [computeStats] folds per-task facts and timer intervals into every
/// figure the tab shows, so the background reader can run it in one go.
library;

import 'catalogue.dart' show TaskStatus, dayRange;
import 'progress.dart' show StagePace;
import 'work_interval.dart';

/// How the period chart is bucketed.
enum StatsBucket { day, week, month }

/// What one task contributes. Archived tasks are not facts (archive =
/// delete).
class StatsFact {
  const StatsFact({
    required this.taskId,
    required this.stageName,
    required this.workId,
    required this.workTitle,
    required this.currency,
    required this.groupKey,
    String? unitKey,
    this.episodeId,
    this.episodeLabel,
    this.partId,
    this.partLabel,
    String? cutKey,
    this.cutLabel,
    this.status,
    this.clientId,
    this.clientName,
    this.clientColor,
    this.take = 1,
    this.submittedAt,
    this.dueAt,
    this.submittedDueAt,
    this.firstDueAt,
    this.dueExtensions = 0,
    this.handedOffAt,
    this.planStartAt,
    this.planEndAt,
    this.pay,
    this.worked = Duration.zero,
  }) : unitKey = unitKey ?? 't$taskId',
       cutKey = cutKey ?? 't$taskId';

  final int taskId;
  final String stageName;
  final int workId;
  final String workTitle;
  final String currency;

  /// The unit the calendar lays out (TaskRow.groupKey).
  final String groupKey;

  /// Where the task sits, for the drill-down ([StatsNode]): its episode
  /// (shown number), part (null: the part-less cuts and storyboards), and
  /// cut (its id, or `s<task id>` for a storyboard) with its label.
  final int? episodeId;
  final String? episodeLabel;
  final int? partId;
  final String? partLabel;
  final String cutKey;
  final String? cutLabel;
  final TaskStatus? status;

  /// What counts as one cut (TaskRow.unitKey): a shared group's tasks of a
  /// stage count once in every cut figure; pay counts per task.
  final String unitKey;
  final int? clientId;
  final String? clientName;
  final int? clientColor;

  /// Highest take (1 = never retaken).
  final int take;

  /// First hand-in — when the cut counts as handed, done and paid
  /// (2026-11-28 유저: 완료와 제출 합침).
  final DateTime? submittedAt;

  /// The production deadline in force now.
  final DateTime? dueAt;

  /// The deadline in force when the task was first handed in — what
  /// adherence is measured against (falls back to [dueAt]).
  final DateTime? submittedDueAt;

  /// The first deadline given (revision 1), and how many times it was
  /// extended since.
  final DateTime? firstDueAt;
  final int dueExtensions;

  /// Handed off to someone else: its timer time counts, its results
  /// (hand-ins, completions, pay, deadlines, progress) do not.
  final DateTime? handedOffAt;
  final DateTime? planStartAt;
  final DateTime? planEndAt;

  /// Amount in the work's currency, smallest unit; null when unpriced.
  final int? pay;

  /// All timer time on the task.
  final Duration worked;
}

/// Money per currency, smallest unit.
typedef Money = Map<String, int>;

/// One bucket of the period chart.
class StatsPeriod {
  StatsPeriod(this.start, this.end);

  /// Local work-day dates; [end] exclusive.
  final DateTime start;
  final DateTime end;
  int handed = 0;
  Duration worked = Duration.zero;

  /// Pay of tasks handed in the bucket.
  final Money earned = {};
}

/// Figures for one group (stage name, work, client).
class StatsSlice {
  StatsSlice(this.key, this.label);

  final Object? key;
  final String? label;

  /// Tasks first handed in the range (2026-11-28 유저: 완료와 제출 합침 —
  /// the old `done` count is this).
  int handed = 0;

  /// Timer time inside the range.
  Duration worked = Duration.zero;

  /// Of [handed]: those with time on them, and that time (whole task).
  int timedHanded = 0;
  Duration timedHandedWorked = Duration.zero;

  /// Of [handed]: retaken at least once.
  int retaken = 0;

  /// Of [handed]: with a deadline, and handed by it.
  int withDue = 0;
  int onTime = 0;

  /// [onTime] of [withDue], 0–1; null with none.
  double? get onTimeRate => withDue == 0 ? null : onTime / withDue;

  /// The first timer time in the range, and the last hand-in.
  DateTime? firstWorkAt;
  DateTime? lastHandedAt;

  /// Progress now, whatever the range: live cuts in the slice, and those
  /// handed in.
  int cuts = 0;
  int finished = 0;

  /// [finished] of [cuts], 0–1; null with no cuts.
  double? get progress => cuts == 0 ? null : finished / cuts;
  final Money earned = {};

  /// Average timer time per handed cut that has time on it.
  Duration? get perCut => timedHanded == 0
      ? null
      : Duration(microseconds: timedHandedWorked.inMicroseconds ~/ timedHanded);

  /// Share of handed cuts that were retaken, 0–1; null with none handed.
  double? get retakeRate => handed == 0 ? null : retaken / handed;

  /// [earned] per hour of [worked], per currency; empty without time.
  Map<String, double> get perHour {
    final hours = worked.inMicroseconds / Duration.microsecondsPerHour;
    if (hours <= 0) return const {};
    return {for (final e in earned.entries) e.key: e.value / hours};
  }
}

/// A level of the statistics drill-down.
enum StatsLevel {
  all,
  client,
  work,
  episode,

  /// A schedule unit: part × stage, the part-less cuts of an episode ×
  /// stage, or one storyboard task (TaskRow.groupKey).
  unit,
  cut,
}

/// One node of the statistics drill-down (유저 2026-11-28): every figure
/// of a [StatsSlice] for the tasks under it — counted by the same rules
/// as [Stats.total], so the root's figures are the total's (a shared
/// group one cut, its pay per cut) — and its [children] in the
/// catalogue's order. A [StatsLevel.cut] leaf is one task (a cut, or a
/// storyboard, at its unit's stage) and counts it, shared group or not.
class StatsNode extends StatsSlice {
  StatsNode._(
    this.level,
    String super.key,
    super.label, {
    this.clientId,
    this.clientColor,
    this.stageName,
  });

  final StatsLevel level;

  /// `all` · `client:3` (`client:none`) · `work:5` · `episode:9` ·
  /// `unit:<group key>` · `cut:88` (`cut:s<task id>` for a storyboard).
  @override
  String get key => super.key! as String;

  final int? clientId;
  final int? clientColor;

  /// The unit's and the cut's stage.
  final String? stageName;

  final List<StatsNode> children = [];

  /// [StatsSlice.onTime] / [StatsSlice.withDue] / [StatsSlice.retaken] /
  /// [StatsSlice.earned] under the names the views use.
  int get dueKept => onTime;
  int get dueTotal => withDue;
  int get retakes => retaken;
  Map<String, int> get payByCurrency => earned;

  /// A cut leaf: its timer time by stage (its one stage).
  Map<String, Duration>? get workedByStage =>
      level == StatsLevel.cut ? {stageName!: worked} : null;

  /// A cut leaf: timer stretches with time in the range, its take, its
  /// pay (paid retakes included, done or not), its status, handed off.
  int? intervals;
  int? retakeRound;
  int? taskPay;
  TaskStatus? status;
  bool handedOff = false;

  void _task(StatsFact f) {
    intervals ??= 0;
    retakeRound = f.take;
    taskPay = f.pay;
    status = f.status;
    handedOff = f.handedOffAt != null;
  }
}

/// One work day of the concurrency chart.
typedef StatsDay = ({DateTime day, int worked, int planned});

/// Everything the statistics tab shows for one range.
class Stats {
  Stats._(this.from, this.to, this.lanes, this.bucket)
    : total = StatsSlice(null, null);

  final DateTime from;
  final DateTime to;
  final int lanes;
  final StatsBucket bucket;

  final StatsSlice total;

  /// Tasks handed off to someone else in the range. Their timer time is in
  /// the time figures; their results are in none.
  int handedOff = 0;

  final List<StatsPeriod> periods = [];
  final List<StatsSlice> stages = [];
  final List<StatsSlice> works = [];
  final List<StatsSlice> clients = [];

  /// The same figures for the range of the same length just before, for
  /// comparison (null on the previous range itself).
  Stats? previous;

  /// Speed per stage name, so far and recent ([CatalogueStore.stagePaces]).
  List<StagePace> stagePaces = const [];

  /// The drill-down, when asked for ([computeStats] `tree`).
  StatsNode? tree;

  /// Hand-ins against the deadline in force when handed in: work days late
  /// (≥1 when past the due instant; 0 = on the due day in time; negative =
  /// early) → cuts. Cuts with no deadline are counted in [noDue].
  final Map<int, int> lateness = {};
  int noDue = 0;

  int get onTime => lateness.entries
      .where((e) => e.key <= 0)
      .fold(0, (sum, e) => sum + e.value);
  int get late => lateness.entries
      .where((e) => e.key > 0)
      .fold(0, (sum, e) => sum + e.value);

  /// The same against the FIRST deadline (revision 1), whatever was
  /// extended since.
  final Map<int, int> latenessFirst = {};

  int get onTimeFirst => latenessFirst.entries
      .where((e) => e.key <= 0)
      .fold(0, (sum, e) => sum + e.value);
  int get lateFirst => latenessFirst.entries
      .where((e) => e.key > 0)
      .fold(0, (sum, e) => sum + e.value);

  /// Handed cuts by how many times their deadline was extended (0 = never).
  final Map<int, int> extensions = {};

  /// Handed cuts whose deadline was extended, by work days gained (current
  /// deadline − first).
  final Map<int, int> extendedDays = {};

  /// Take → handed cuts that reached it (1 = right first time).
  final Map<int, int> takes = {};

  /// Timer time by local weekday (index 0 = Monday) and hour of day.
  final List<List<Duration>> heatmap = List.generate(
    7,
    (_) => List.filled(24, Duration.zero),
  );

  /// Per work day: groups with timer time that day, and groups whose plan
  /// covers it — against [lanes].
  final List<StatsDay> days = [];

  /// Money per hour by currency, over tasks handed in the range that have
  /// timer time (their whole time); smallest unit per hour.
  final Map<String, double> hourly = {};
}

/// The local work-day date [t] belongs to (the day starts at
/// [dayStartMinutes] past midnight).
DateTime workDayOf(DateTime t, int dayStartMinutes) {
  // [dayRange]'s rule, with two dates built instead of five (it runs for
  // every fact and stretch of a year's statistics).
  final local = t.toLocal();
  final midnight = DateTime(local.year, local.month, local.day);
  return local.isBefore(midnight.add(Duration(minutes: dayStartMinutes)))
      ? DateTime(local.year, local.month, local.day - 1)
      : midnight;
}

/// Folds [facts] and [intervals] into [Stats] for the work days
/// `[from, to)` (local dates): the periods, the facts (counts, deadlines,
/// pay), the timer (time, heatmap, groups worked per day), the planned
/// groups per day, then the slices in order.
Stats computeStats({
  required List<StatsFact> facts,
  required List<WorkInterval> intervals,
  required DateTime from,
  required DateTime to,
  required DateTime now,
  StatsBucket bucket = StatsBucket.week,
  int dayStartMinutes = 0,
  int weekStart = DateTime.monday,
  int lanes = 2,
  bool tree = false,
}) {
  from = DateTime(from.year, from.month, from.day);
  to = DateTime(to.year, to.month, to.day);
  final fold = _StatsFold(
    Stats._(from, to, lanes, bucket),
    dayStartMinutes,
    tree ? StatsNode._(StatsLevel.all, 'all', null) : null,
  );
  fold.s.tree = fold.tree;
  for (var p = _bucketStart(from, bucket, weekStart); p.isBefore(to);) {
    final next = _nextBucket(p, bucket);
    fold.s.periods.add(StatsPeriod(p, next));
    p = next;
  }
  facts.forEach(fold.fact);
  fold.hourly();
  final workedGroups = fold.timer(intervals, facts, now);
  fold.days(facts, workedGroups);
  return fold.ordered();
}

/// One run of [computeStats]: the stats being filled and what its steps
/// share.
class _StatsFold {
  _StatsFold(this.s, this.dayStartMinutes, this.tree);

  final Stats s;
  final int dayStartMinutes;
  final stages = <String, StatsSlice>{};
  final works = <int, StatsSlice>{};
  final clients = <int?, StatsSlice>{};
  final _hourlyPay = <String, int>{};
  final _hourlyTime = <String, Duration>{};

  // Deadlines and plans repeat across a part's cuts: each instant once.
  final _days = <int, DateTime>{};
  DateTime day(DateTime t) =>
      _days[t.millisecondsSinceEpoch] ??= workDayOf(t, dayStartMinutes);

  bool inRange(DateTime? t) {
    if (t == null) return false;
    final d = day(t);
    return !d.isBefore(s.from) && d.isBefore(s.to);
  }

  StatsPeriod? periodOf(DateTime t) {
    final d = day(t);
    for (final p in s.periods) {
      if (!d.isBefore(p.start) && d.isBefore(p.end)) return p;
    }
    return null;
  }

  /// Counts one task: handed over (and paid), deadlines kept — into
  /// the total, its stage, work and client, and (with a tree) every node
  /// on its path; its cut leaf counts it whatever its shared group.
  void fact(StatsFact f) {
    final slices = <StatsSlice>[
      s.total,
      stages.putIfAbsent(
        f.stageName,
        () => StatsSlice(f.stageName, f.stageName),
      ),
      works.putIfAbsent(f.workId, () => StatsSlice(f.workId, f.workTitle)),
      clients.putIfAbsent(
        f.clientId,
        () => StatsSlice(f.clientId, f.clientName),
      ),
      ..._pathOf(f),
    ];
    final leaf = _leafOf(f);
    leaf?._task(f);
    // Handed off: the slices exist (its time is counted later), its
    // results are not.
    if (f.handedOffAt != null) {
      if (inRange(f.handedOffAt)) s.handedOff++;
      return;
    }
    if (_units.add(f.unitKey)) {
      _count(f, slices, global: true);
    } else {
      // A shared group's other tasks: their pay and time, not another cut.
      if (inRange(f.submittedAt)) {
        for (final x in slices) {
          x.timedHandedWorked += f.worked;
        }
        _paid(f, slices, periodOf(f.submittedAt!));
      }
    }
    if (leaf != null) _count(f, [leaf], global: false);
  }

  final _units = <String>{};

  /// One task's counts into [slices]; [global] also counts it in the
  /// range's own figures (periods, takes, deadlines, hourly pay).
  void _count(StatsFact f, List<StatsSlice> slices, {required bool global}) {
    for (final x in slices) {
      x.cuts++;
      if (f.submittedAt != null) x.finished++;
    }
    if (inRange(f.submittedAt)) _handed(f, slices, global: global);
  }

  void _handed(StatsFact f, List<StatsSlice> slices, {required bool global}) {
    final handedAt = f.submittedAt!;
    int lateBy(DateTime due) {
      var days = (day(handedAt).difference(day(due)).inHours / 24).round();
      if (handedAt.isAfter(due) && days < 1) days = 1;
      if (!handedAt.isAfter(due) && days > 0) days = 0;
      return days;
    }

    final due = f.submittedDueAt ?? f.dueAt;
    final kept = due != null && lateBy(due) <= 0;
    final timed = f.worked > Duration.zero;
    for (final x in slices) {
      x.handed++;
      if (timed) {
        x.timedHanded++;
        x.timedHandedWorked += f.worked;
      }
      if (f.take > 1) x.retaken++;
      if (due != null) x.withDue++;
      if (kept) x.onTime++;
      final last = x.lastHandedAt;
      if (last == null || handedAt.isAfter(last)) x.lastHandedAt = handedAt;
    }
    if (!global) {
      _earn(f, slices);
      return;
    }
    final period = periodOf(handedAt);
    period?.handed++;
    _paid(f, slices, period);
    s.takes.update(f.take, (n) => n + 1, ifAbsent: () => 1);
    if (due == null) {
      s.noDue++;
      return;
    }
    s.lateness.update(lateBy(due), (n) => n + 1, ifAbsent: () => 1);
    final first = f.firstDueAt ?? due;
    s.latenessFirst.update(lateBy(first), (n) => n + 1, ifAbsent: () => 1);
    s.extensions.update(f.dueExtensions, (n) => n + 1, ifAbsent: () => 1);
    if (f.dueExtensions > 0 && f.dueAt != null) {
      final gained = (day(f.dueAt!).difference(day(first)).inHours / 24)
          .round();
      s.extendedDays.update(gained, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  /// A handed task's pay into [slices] only.
  void _earn(StatsFact f, List<StatsSlice> slices) {
    final pay = f.pay;
    if (pay == null) return;
    for (final x in slices) {
      x.earned.update(f.currency, (v) => v + pay, ifAbsent: () => pay);
    }
  }

  /// A handed task's pay into the slices, its period and the hourly pay.
  void _paid(StatsFact f, List<StatsSlice> slices, StatsPeriod? period) {
    final pay = f.pay;
    if (pay == null) return;
    _earn(f, slices);
    period?.earned.update(f.currency, (v) => v + pay, ifAbsent: () => pay);
    if (f.worked > Duration.zero) {
      _hourlyPay.update(f.currency, (v) => v + pay, ifAbsent: () => pay);
      _hourlyTime.update(
        f.currency,
        (v) => v + f.worked,
        ifAbsent: () => f.worked,
      );
    }
  }

  // ---- the drill-down tree (client → work → episode → unit → cut) ----

  final StatsNode? tree;
  final _nodes = <String, StatsNode>{};

  StatsNode _child(StatsNode parent, String path, StatsNode Function() make) =>
      _nodes[path] ??= () {
        final n = make();
        parent.children.add(n);
        return n;
      }();

  /// [f]'s nodes above its cut: the root, its client, work, episode and
  /// unit.
  List<StatsNode> _pathOf(StatsFact f) {
    final root = tree;
    if (root == null) return const [];
    final clientKey = 'client:${f.clientId ?? 'none'}';
    final client = _child(
      root,
      clientKey,
      () => StatsNode._(
        StatsLevel.client,
        clientKey,
        f.clientName,
        clientId: f.clientId,
        clientColor: f.clientColor,
      ),
    );
    final work = _child(
      client,
      'work:${f.workId}',
      () => StatsNode._(
        StatsLevel.work,
        'work:${f.workId}',
        f.workTitle,
        clientId: f.clientId,
        clientColor: f.clientColor,
      ),
    );
    final episode = _child(
      work,
      'episode:${f.episodeId}',
      () => StatsNode._(
        StatsLevel.episode,
        'episode:${f.episodeId}',
        f.episodeLabel,
        clientId: f.clientId,
        clientColor: f.clientColor,
      ),
    );
    final unit = _child(
      episode,
      'unit:${f.groupKey}',
      () => StatsNode._(
        StatsLevel.unit,
        'unit:${f.groupKey}',
        f.partId == null && f.cutKey.startsWith('s') ? f.cutLabel : f.partLabel,
        clientId: f.clientId,
        clientColor: f.clientColor,
        stageName: f.stageName,
      ),
    );
    return [root, client, work, episode, unit];
  }

  StatsNode? _leafOf(StatsFact f) {
    if (tree == null) return null;
    return _child(
      _nodes['unit:${f.groupKey}']!,
      _leafPath(f),
      () => StatsNode._(
        StatsLevel.cut,
        'cut:${f.cutKey}',
        f.cutLabel,
        clientId: f.clientId,
        clientColor: f.clientColor,
        stageName: f.stageName,
      ),
    );
  }

  static String _leafPath(StatsFact f) => 'unit:${f.groupKey}|${f.cutKey}';

  /// [f]'s tree nodes for the timer: its path and its cut.
  List<StatsNode> _timedNodes(StatsFact f) {
    if (tree == null) return const [];
    return [
      tree!,
      _nodes['client:${f.clientId ?? 'none'}']!,
      _nodes['work:${f.workId}']!,
      _nodes['episode:${f.episodeId}']!,
      _nodes['unit:${f.groupKey}']!,
      _nodes[_leafPath(f)]!,
    ];
  }

  /// Pay per hour of timed, finished work, per currency.
  void hourly() {
    for (final c in _hourlyPay.keys) {
      final hours = _hourlyTime[c]!.inSeconds / 3600;
      if (hours > 0) s.hourly[c] = _hourlyPay[c]! / hours;
    }
  }

  /// Timer time into the periods, slices and heatmap; answers the groups
  /// worked on each work day.
  Map<DateTime, Set<String>> timer(
    List<WorkInterval> intervals,
    List<StatsFact> facts,
    DateTime now,
  ) {
    final factOf = {for (final f in facts) f.taskId: f};
    final rangeStart = s.from.add(Duration(minutes: dayStartMinutes));
    final rangeEnd = s.to.add(Duration(minutes: dayStartMinutes));
    final workedGroups = <DateTime, Set<String>>{};
    for (final i in intervals) {
      var a = i.start.toLocal();
      var b = (i.stop ?? now).toLocal();
      if (a.isBefore(rangeStart)) a = rangeStart;
      if (b.isAfter(rangeEnd)) b = rangeEnd;
      if (!b.isAfter(a)) continue;
      final fact = factOf[i.taskId];
      final length = b.difference(a);
      s.total.worked += length;
      if (fact != null) {
        stages[fact.stageName]!.worked += length;
        works[fact.workId]!.worked += length;
        clients[fact.clientId]!.worked += length;
        final nodes = _timedNodes(fact);
        for (final n in nodes) {
          n.worked += length;
          final first = n.firstWorkAt;
          if (first == null || a.isBefore(first)) n.firstWorkAt = a.toUtc();
        }
        if (nodes.isNotEmpty) nodes.last.intervals = nodes.last.intervals! + 1;
      }
      // Walk the stretch hour by hour (wall clock) for the heatmap, and by
      // work day for the periods and the concurrency chart.
      var t = a;
      while (t.isBefore(b)) {
        final hourEnd = DateTime(t.year, t.month, t.day, t.hour + 1);
        final dayEnd = dayRange(t, dayStartMinutes).end;
        var end = hourEnd.isBefore(dayEnd) ? hourEnd : dayEnd;
        if (end.isAfter(b)) end = b;
        final piece = end.difference(t);
        s.heatmap[t.weekday - 1][t.hour] += piece;
        periodOf(t)?.worked += piece;
        if (fact != null) {
          (workedGroups[day(t)] ??= {}).add(fact.groupKey);
        }
        t = end;
      }
    }
    return workedGroups;
  }

  /// Each work day: groups worked on, and groups planned to be in hand.
  void days(List<StatsFact> facts, Map<DateTime, Set<String>> workedGroups) {
    final plans = <String, ({DateTime start, DateTime end})>{};
    for (final f in facts) {
      if (f.handedOffAt != null) continue;
      final a = f.planStartAt;
      final b = f.planEndAt;
      if (a == null || b == null) continue;
      final span = (start: day(a), end: day(b));
      final had = plans[f.groupKey];
      plans[f.groupKey] = had == null
          ? span
          : (
              start: span.start.isBefore(had.start) ? span.start : had.start,
              end: span.end.isAfter(had.end) ? span.end : had.end,
            );
    }
    // Planned groups per day: +1 where a plan starts, −1 after it ends,
    // summed along the range (not every plan against every day).
    final dates = [
      for (
        var d = s.from;
        d.isBefore(s.to);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    int indexOf(DateTime d) => (d.difference(s.from).inHours / 24).round();
    final change = List.filled(dates.length + 1, 0);
    for (final p in plans.values) {
      final a = indexOf(p.start);
      final b = indexOf(p.end);
      if (b < 0 || a >= dates.length) continue;
      change[a < 0 ? 0 : a]++;
      change[b + 1 > dates.length ? dates.length : b + 1]--;
    }
    var planned = 0;
    for (var i = 0; i < dates.length; i++) {
      planned += change[i];
      s.days.add((
        day: dates[i],
        worked: workedGroups[dates[i]]?.length ?? 0,
        planned: planned,
      ));
    }
  }

  /// The slices that were used, most handed over first.
  Stats ordered() {
    int byHanded(StatsSlice a, StatsSlice b) => b.handed != a.handed
        ? b.handed.compareTo(a.handed)
        : b.worked.compareTo(a.worked);
    bool used(StatsSlice x) => x.handed > 0 || x.worked > Duration.zero;
    s.stages.addAll(stages.values.where(used).toList()..sort(byHanded));
    s.works.addAll(works.values.where(used).toList()..sort(byHanded));
    s.clients.addAll(clients.values.where(used).toList()..sort(byHanded));
    return s;
  }
}

DateTime _bucketStart(DateTime d, StatsBucket bucket, int weekStart) =>
    switch (bucket) {
      StatsBucket.day => d,
      StatsBucket.week => DateTime(
        d.year,
        d.month,
        d.day - (d.weekday - weekStart + 7) % 7,
      ),
      StatsBucket.month => DateTime(d.year, d.month),
    };

DateTime _nextBucket(DateTime d, StatsBucket bucket) => switch (bucket) {
  StatsBucket.day => DateTime(d.year, d.month, d.day + 1),
  StatsBucket.week => DateTime(d.year, d.month, d.day + 7),
  StatsBucket.month => DateTime(d.year, d.month + 1),
};
