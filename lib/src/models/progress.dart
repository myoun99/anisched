/// Read models for the views: one row per task, rolled up into part × stage
/// groups. Pure Dart — filled by the services layer.
library;

import 'catalogue.dart';

/// One live task with everything the views show about it.
class TaskRow {
  const TaskRow({
    required this.id,
    required this.status,
    required this.take,
    required this.workId,
    required this.workTitle,
    required this.currency,
    required this.episodeId,
    required this.episodeNumber,
    required this.stageId,
    required this.stageName,
    this.cutId,
    this.cutNumber,
    this.lengthMs,
    this.storyboardId,
    this.storyboardLabel,
    this.partId,
    this.partLabel,
    this.plannedCutCount,
    this.receivedAt,
    this.ownDueAt,
    this.partDueAt,
    this.ownPlanStartAt,
    this.ownPlanEndAt,
    this.partPlanStartAt,
    this.partPlanEndAt,
    this.pay,
    this.worked = Duration.zero,
  });

  final int id;
  final TaskStatus status;

  /// 1 for the first take, 2 for T2, …
  final int take;
  final int workId;
  final String workTitle;
  final String currency;
  final int episodeId;
  final String episodeNumber;
  final int stageId;
  final String stageName;
  final int? cutId;
  final String? cutNumber;
  final int? lengthMs;
  final int? storyboardId;
  final String? storyboardLabel;
  final int? partId;
  final String? partLabel;
  final int? plannedCutCount;
  final DateTime? receivedAt;

  /// The task's own deadline, if it set one.
  final DateTime? ownDueAt;

  /// The part's deadline for this stage, if any.
  final DateTime? partDueAt;

  /// The user's own plan for this cut, if set (overrides the part's).
  final DateTime? ownPlanStartAt;
  final DateTime? ownPlanEndAt;

  /// The user's plan for the part × stage, if any.
  final DateTime? partPlanStartAt;
  final DateTime? partPlanEndAt;

  /// Pay including paid retakes, or null when it cannot be computed yet.
  final int? pay;

  /// Timer time recorded on this task.
  final Duration worked;

  /// The deadline that applies: the task's own, else its part's.
  DateTime? get dueAt => ownDueAt ?? partDueAt;

  /// True when [dueAt] is the part's deadline (the task set none).
  bool get dueFromPart => ownDueAt == null && partDueAt != null;

  /// When the user plans to start: the cut's own, else the part's.
  DateTime? get planStartAt => ownPlanStartAt ?? partPlanStartAt;

  /// When the user plans to finish: the cut's own, else the part's.
  DateTime? get planEndAt => ownPlanEndAt ?? partPlanEndAt;

  /// True when a cut in a part carries its own plan (either end).
  bool get planOverridden =>
      partId != null && (ownPlanStartAt != null || ownPlanEndAt != null);

  /// Days between planned finish and deadline; negative = planned late.
  int? get slackDays => _slack(planEndAt, dueAt);

  /// True when a cut in a part carries its own deadline.
  bool get dueOverridden => partId != null && ownDueAt != null;

  /// The cut number, or the storyboard label for a storyboard task.
  String get unitLabel => cutNumber ?? storyboardLabel ?? '';

  bool get isOpen => status.isOpen;

  /// The rows that make one schedule unit share this key: a part × stage;
  /// the "no part" cuts of an episode × stage; or a storyboard task alone.
  String get groupKey => storyboardId != null
      ? 'storyboard:$id'
      : partId == null
      ? 'nopart:$episodeId:$stageId'
      : 'part:$partId:$stageId';
}

extension TaskStatusRules on TaskStatus {
  /// Still in the user's hands.
  bool get isOpen =>
      this == TaskStatus.received ||
      this == TaskStatus.inProgress ||
      this == TaskStatus.retake;

  /// Handed over (submitted or done).
  bool get isHanded => this == TaskStatus.submitted || this == TaskStatus.done;

  /// Sort order when urgency matters: retake first, done last.
  int get urgency => switch (this) {
    TaskStatus.retake => 0,
    TaskStatus.inProgress => 1,
    TaskStatus.received => 2,
    TaskStatus.submitted => 3,
    TaskStatus.done => 4,
  };
}

/// The status of a group from its tasks' statuses: all done → done; any
/// retake → retake; all handed → submitted; all received → received;
/// otherwise in progress.
TaskStatus deriveStatus(Map<TaskStatus, int> counts) {
  final total = counts.values.fold(0, (a, b) => a + b);
  int n(TaskStatus s) => counts[s] ?? 0;
  if (total == 0 || n(TaskStatus.received) == total) {
    return TaskStatus.received;
  }
  if (n(TaskStatus.done) == total) return TaskStatus.done;
  if (n(TaskStatus.retake) > 0) return TaskStatus.retake;
  if (n(TaskStatus.submitted) + n(TaskStatus.done) == total) {
    return TaskStatus.submitted;
  }
  return TaskStatus.inProgress;
}

/// What kind of schedule unit a [PartGroup] is.
enum GroupKind {
  /// A part × stage.
  part,

  /// An episode's cuts outside any part, for one stage.
  noPart,

  /// One storyboard task, a unit on its own.
  storyboard,
}

/// The name the views use for a schedule unit.
typedef PartStageRow = PartGroup;

/// A schedule unit: a part × stage with its cut tasks, the part-less cuts
/// of an episode × stage, or one storyboard task.
class PartGroup {
  PartGroup(this.tasks) : assert(tasks.isNotEmpty);

  /// The group's tasks, in cut order.
  final List<TaskRow> tasks;

  TaskRow get _first => tasks.first;
  String get key => _first.groupKey;

  GroupKind get kind => _first.storyboardId != null
      ? GroupKind.storyboard
      : _first.partId == null
      ? GroupKind.noPart
      : GroupKind.part;
  int get workId => _first.workId;
  int get episodeId => _first.episodeId;
  String get workTitle => _first.workTitle;
  String get currency => _first.currency;
  String get episodeNumber => _first.episodeNumber;
  int get stageId => _first.stageId;
  String get stageName => _first.stageName;
  int? get partId => _first.partId;
  int? get plannedCutCount => _first.plannedCutCount;

  /// The part's label; null for [GroupKind.noPart] (the views say
  /// "no part") and for a storyboard.
  String? get partLabel => _first.partLabel;

  /// The storyboard's label for [GroupKind.storyboard].
  String? get storyboardLabel => _first.storyboardLabel;

  int get total => tasks.length;

  Map<TaskStatus, int> get counts {
    final c = <TaskStatus, int>{};
    for (final t in tasks) {
      c[t.status] = (c[t.status] ?? 0) + 1;
    }
    return c;
  }

  /// Tasks submitted or done — the 3 in "3/6".
  int get handed => tasks.where((t) => t.status.isHanded).length;

  TaskStatus get status => deriveStatus(counts);

  /// The part's deadline for the stage; for a storyboard, its task's; for
  /// part-less cuts, the earliest of their deadlines.
  DateTime? get dueAt => switch (kind) {
    GroupKind.part => _first.partDueAt,
    GroupKind.storyboard => _first.dueAt,
    GroupKind.noPart => _earliest(tasks.map((t) => t.dueAt)),
  };

  /// The user's planned start: the part's; for a storyboard, its task's;
  /// for part-less cuts, the earliest.
  DateTime? get planStartAt => switch (kind) {
    GroupKind.part => _first.partPlanStartAt,
    GroupKind.storyboard => _first.planStartAt,
    GroupKind.noPart => _earliest(tasks.map((t) => t.planStartAt)),
  };

  /// The user's planned finish: the part's; for a storyboard, its task's;
  /// for part-less cuts, the latest.
  DateTime? get planEndAt => switch (kind) {
    GroupKind.part => _first.partPlanEndAt,
    GroupKind.storyboard => _first.planEndAt,
    GroupKind.noPart => _latest(tasks.map((t) => t.planEndAt)),
  };

  /// Days of margin between the planned finish and the deadline;
  /// negative = the plan runs past the deadline. Null if either is unset.
  int? get slackDays => _slack(planEndAt, dueAt);

  /// When the earliest task arrived.
  DateTime? get startAt => _earliest(tasks.map((t) => t.receivedAt));

  /// Sum of computable pay, in [currency].
  int get pay => tasks.fold(0, (a, t) => a + (t.pay ?? 0));

  /// Tasks whose pay cannot be computed yet.
  int get unpriced => tasks.where((t) => t.pay == null).length;

  Duration get worked => tasks.fold(Duration.zero, (a, t) => a + t.worked);
}

int? _slack(DateTime? planEnd, DateTime? due) =>
    planEnd == null || due == null ? null : daysBetween(planEnd, due);

DateTime? _latest(Iterable<DateTime?> times) {
  DateTime? l;
  for (final t in times) {
    if (t != null && (l == null || t.isAfter(l))) l = t;
  }
  return l;
}

DateTime? _earliest(Iterable<DateTime?> times) {
  DateTime? e;
  for (final t in times) {
    if (t != null && (e == null || t.isBefore(e))) e = t;
  }
  return e;
}

/// Rolls [rows] (already in display order) into groups and sorts them by
/// deadline, no deadline last; ties keep display order.
List<PartGroup> groupRows(Iterable<TaskRow> rows) {
  final byKey = <String, List<TaskRow>>{};
  for (final r in rows) {
    (byKey[r.groupKey] ??= []).add(r);
  }
  final groups = [for (final list in byKey.values) PartGroup(list)];
  final order = {for (var i = 0; i < groups.length; i++) groups[i]: i};
  groups.sort((a, b) {
    final da = a.dueAt;
    final db = b.dueAt;
    if (da != db) {
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      if (c != 0) return c;
    }
    return order[a]!.compareTo(order[b]!);
  });
  return groups;
}

/// Whole calendar days from [from] to [to], by their local dates.
int daysBetween(DateTime from, DateTime to) {
  final a = from.toLocal();
  final b = to.toLocal();
  return DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

/// Days from the working day of [now] to the working day [due] falls on,
/// with days starting [dayStartMinutes] after midnight. Negative = late.
int dueInDays(DateTime due, DateTime now, int dayStartMinutes) => daysBetween(
  dayRange(now, dayStartMinutes).start,
  dayRange(due, dayStartMinutes).start,
);

/// Which end a pace counts down to.
enum PaceEnd {
  /// The user's planned finish, falling back to the deadline.
  plan('plan'),

  /// The production deadline.
  due('due');

  const PaceEnd(this.dbName);

  final String dbName;

  static PaceEnd fromDb(String s) => values.firstWhere((v) => v.dbName == s);
}

/// How fast a group must go: [remaining] open cuts over [workDays] working
/// days, from today (or the planned start, if later) to the end day
/// inclusive, skipping rest weekdays.
class Pace {
  const Pace({
    required this.remaining,
    required this.workDays,
    required this.startsLater,
    required this.end,
    this.restToday = false,
  });

  /// Cuts not yet handed over (received, in progress, retake).
  final int remaining;

  /// Working days left, today and the end day included. 0 when the end
  /// day has passed or every day left is a rest day.
  final int workDays;

  /// True when the planned start is after today.
  final bool startsLater;

  /// The end the pace counts to.
  final DateTime end;

  /// True when today is a rest weekday or a day off.
  final bool restToday;

  /// Cuts per working day, or null when no working day is left.
  double? get perDay => workDays == 0 ? null : remaining / workDays;

  /// True when cuts remain and no working day is left.
  bool get behind => remaining > 0 && workDays == 0;

  /// What today asks for: the per-day pace; 0 before the planned start or
  /// on a rest day; everything left once no working day remains.
  double get today =>
      startsLater || restToday ? 0 : (perDay ?? remaining.toDouble());
}

/// A run of calendar days off, both ends included. Dates are compared by
/// their year, month and day only.
class DaysOff {
  DaysOff(DateTime start, [DateTime? end])
    : start = _date(start),
      end = _date(end ?? start) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Days off cannot end before they start.');
    }
  }

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final d = _date(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static DateTime _date(DateTime t) => DateTime.utc(t.year, t.month, t.day);
}

/// The pace for [group] as of [now], or null when it has no end date.
/// [restWeekdays] uses [DateTime.weekday] (1 = Monday … 7 = Sunday);
/// [daysOff] adds specific days. Both are skipped when counting days.
Pace? paceFor(
  PartGroup group,
  DateTime now, {
  int dayStartMinutes = 0,
  Set<int> restWeekdays = const {},
  Iterable<DaysOff> daysOff = const [],
  PaceEnd endAt = PaceEnd.plan,
}) {
  bool off(DateTime d) =>
      restWeekdays.contains(d.weekday) || daysOff.any((r) => r.contains(d));

  final endTime = switch (endAt) {
    PaceEnd.plan => group.planEndAt ?? group.dueAt,
    PaceEnd.due => group.dueAt,
  };
  if (endTime == null) return null;
  DateTime dateOf(DateTime t) {
    final d = dayRange(t, dayStartMinutes).start;
    return DateTime.utc(d.year, d.month, d.day);
  }

  final today = dateOf(now);
  final planStart = group.planStartAt;
  final startsLater = planStart != null && dateOf(planStart).isAfter(today);
  final from = startsLater ? dateOf(planStart) : today;
  final to = dateOf(endTime);
  var workDays = 0;
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    if (!off(d)) workDays++;
  }
  return Pace(
    remaining: group.tasks.where((t) => t.isOpen).length,
    workDays: workDays,
    startsLater: startsLater,
    end: endTime,
    restToday: off(today),
  );
}
