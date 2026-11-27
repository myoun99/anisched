/// The statistics tab's numbers (docs/data-model.md, 통계).
///
/// Pure: [computeStats] folds per-task facts and timer intervals into every
/// figure the tab shows, so the background reader can run it in one go.
library;

import 'catalogue.dart' show dayRange;
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
    this.clientId,
    this.clientName,
    this.take = 1,
    this.submittedAt,
    this.doneAt,
    this.dueAt,
    this.planStartAt,
    this.planEndAt,
    this.pay,
    this.worked = Duration.zero,
  });

  final int taskId;
  final String stageName;
  final int workId;
  final String workTitle;
  final String currency;

  /// The unit the calendar lays out (TaskRow.groupKey).
  final String groupKey;
  final int? clientId;
  final String? clientName;

  /// Highest take (1 = never retaken).
  final int take;

  /// First hand-in.
  final DateTime? submittedAt;
  final DateTime? doneAt;

  /// The production deadline in force.
  final DateTime? dueAt;
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
  int done = 0;
  Duration worked = Duration.zero;

  /// Pay of tasks done in the bucket.
  final Money earned = {};
}

/// Figures for one group (stage name, work, client).
class StatsSlice {
  StatsSlice(this.key, this.label);

  final Object? key;
  final String? label;

  /// Tasks first handed in the range.
  int handed = 0;
  int done = 0;

  /// Timer time inside the range.
  Duration worked = Duration.zero;

  /// Of [handed]: those with time on them, and that time (whole task).
  int timedHanded = 0;
  Duration timedHandedWorked = Duration.zero;

  /// Of [handed]: retaken at least once.
  int retaken = 0;
  final Money earned = {};

  /// Average timer time per handed cut that has time on it.
  Duration? get perCut => timedHanded == 0
      ? null
      : Duration(microseconds: timedHandedWorked.inMicroseconds ~/ timedHanded);

  /// Share of handed cuts that were retaken, 0–1; null with none handed.
  double? get retakeRate => handed == 0 ? null : retaken / handed;
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
  final List<StatsPeriod> periods = [];
  final List<StatsSlice> stages = [];
  final List<StatsSlice> works = [];
  final List<StatsSlice> clients = [];

  /// Hand-ins against their deadline: days late (negative = early, 0 = the
  /// due day) → cuts. Cuts with no deadline are counted in [noDue].
  final Map<int, int> lateness = {};
  int noDue = 0;

  int get onTime => lateness.entries
      .where((e) => e.key <= 0)
      .fold(0, (sum, e) => sum + e.value);
  int get late => lateness.entries
      .where((e) => e.key > 0)
      .fold(0, (sum, e) => sum + e.value);

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

  /// Money per hour by currency, over tasks done in the range that have
  /// timer time (their whole time); smallest unit per hour.
  final Map<String, double> hourly = {};
}

/// The local work-day date [t] belongs to (the day starts at
/// [dayStartMinutes] past midnight).
DateTime workDayOf(DateTime t, int dayStartMinutes) {
  final start = dayRange(t, dayStartMinutes).start;
  return DateTime(start.year, start.month, start.day);
}

/// Folds [facts] and [intervals] into [Stats] for the work days
/// `[from, to)` (local dates).
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
}) {
  from = DateTime(from.year, from.month, from.day);
  to = DateTime(to.year, to.month, to.day);
  final s = Stats._(from, to, lanes, bucket);
  DateTime day(DateTime t) => workDayOf(t, dayStartMinutes);
  bool inRange(DateTime? t) {
    if (t == null) return false;
    final d = day(t);
    return !d.isBefore(from) && d.isBefore(to);
  }

  // Periods.
  for (var p = _bucketStart(from, bucket, weekStart); p.isBefore(to);) {
    final next = _nextBucket(p, bucket);
    s.periods.add(StatsPeriod(p, next));
    p = next;
  }
  StatsPeriod? periodOf(DateTime t) {
    final d = day(t);
    for (final p in s.periods) {
      if (!d.isBefore(p.start) && d.isBefore(p.end)) return p;
    }
    return null;
  }

  final stages = <String, StatsSlice>{};
  final works = <int, StatsSlice>{};
  final clients = <int?, StatsSlice>{};
  final factOf = {for (final f in facts) f.taskId: f};
  final hourlyPay = <String, int>{};
  final hourlyTime = <String, Duration>{};

  for (final f in facts) {
    final slices = [
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
    ];
    if (inRange(f.submittedAt)) {
      final timed = f.worked > Duration.zero;
      for (final x in slices) {
        x.handed++;
        if (timed) {
          x.timedHanded++;
          x.timedHandedWorked += f.worked;
        }
        if (f.take > 1) x.retaken++;
      }
      periodOf(f.submittedAt!)?.handed++;
      s.takes.update(f.take, (n) => n + 1, ifAbsent: () => 1);
      final due = f.dueAt;
      if (due == null) {
        s.noDue++;
      } else {
        final late = day(f.submittedAt!).difference(day(due)).inHours;
        s.lateness.update((late / 24).round(), (n) => n + 1, ifAbsent: () => 1);
      }
    }
    if (inRange(f.doneAt)) {
      final period = periodOf(f.doneAt!);
      period?.done++;
      for (final x in slices) {
        x.done++;
      }
      final pay = f.pay;
      if (pay != null) {
        for (final x in slices) {
          x.earned.update(f.currency, (v) => v + pay, ifAbsent: () => pay);
        }
        period?.earned.update(f.currency, (v) => v + pay, ifAbsent: () => pay);
        if (f.worked > Duration.zero) {
          hourlyPay.update(f.currency, (v) => v + pay, ifAbsent: () => pay);
          hourlyTime.update(
            f.currency,
            (v) => v + f.worked,
            ifAbsent: () => f.worked,
          );
        }
      }
    }
  }
  for (final c in hourlyPay.keys) {
    final hours = hourlyTime[c]!.inSeconds / 3600;
    if (hours > 0) s.hourly[c] = hourlyPay[c]! / hours;
  }

  // Timer time: periods, slices, heatmap, worked groups per day.
  final rangeStart = from.add(Duration(minutes: dayStartMinutes));
  final rangeEnd = to.add(Duration(minutes: dayStartMinutes));
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

  // Concurrency per work day.
  final plans = <String, ({DateTime start, DateTime end})>{};
  for (final f in facts) {
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
  for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
    var planned = 0;
    for (final p in plans.values) {
      if (!d.isBefore(p.start) && !d.isAfter(p.end)) planned++;
    }
    s.days.add((
      day: d,
      worked: workedGroups[d]?.length ?? 0,
      planned: planned,
    ));
  }

  int byHanded(StatsSlice a, StatsSlice b) => b.handed != a.handed
      ? b.handed.compareTo(a.handed)
      : b.worked.compareTo(a.worked);
  bool used(StatsSlice x) =>
      x.handed > 0 || x.done > 0 || x.worked > Duration.zero;
  s.stages.addAll(stages.values.where(used).toList()..sort(byHanded));
  s.works.addAll(works.values.where(used).toList()..sort(byHanded));
  s.clients.addAll(clients.values.where(used).toList()..sort(byHanded));
  return s;
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
