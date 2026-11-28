/// Read models for the views: one row per task, rolled up into part × stage
/// groups. Pure Dart — filled by the services layer.
library;

import 'catalogue.dart';
import 'cut_numbers.dart';

/// One cut of an episode, as the registration grid shows it. A cut in a
/// shared (겸용) group carries the group's first cut and label; an
/// archived cut (a missing number taken out) is [archived].
/// A client (회사) as the pickers and settings show it. [color] is an ARGB
/// value the user picked (유저 2026-11-28); null shows the default grey.
/// What the registration lists can rename and, when not [CatalogueKind]
/// in use, delete (유저 2026-11-28).
enum CatalogueKind { client, work, episode, part }

/// A client; [inUse]: a work has it (archived ones too) — it cannot be
/// deleted. Likewise for [WorkRow], [EpisodeRow] and [PartRow].
typedef ClientRow = ({
  int id,
  String name,
  int? closingDay,
  int? color,
  bool inUse,
});

typedef WorkRow = ({
  int id,
  String title,
  String currency,
  int? clientId,
  bool inUse,
});

typedef EpisodeRow = ({int id, String number, String? title, bool inUse});

typedef PartRow = ({
  int id,
  String label,
  int? plannedCutCount,
  int cutCount,
  bool inUse,
});

/// Something on the calendar that is not work (유저 2026-11-28 — 아후레코,
/// a meeting): a day, an optional time of day in minutes, a title and a
/// note. [episodeId] ties it to an episode's timeline rows; null is a
/// global event. A global event with [rest] is a day off (유저
/// 2026-11-28) — the pace skips it like a rest weekday.
typedef EventRow = ({
  int id,
  int? episodeId,
  DateTime date,
  int? timeMinutes,
  String title,
  String? note,
  bool rest,
});

typedef CutRow = ({
  int id,
  String number,
  int? lengthMs,
  int? partId,
  int? sharedHeadCutId,
  String? sharedLabel,
  bool archived,
});

/// One live task with everything the views show about it.
class TaskRow {
  const TaskRow({
    required this.id,
    required this.status,
    required this.take,
    required this.workId,
    required this.workTitle,
    this.clientName,
    this.clientColor,
    required this.currency,
    required this.episodeId,
    required this.episodeNumber,
    required this.stageId,
    required this.stageName,
    this.stagePosition = 0,
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
    this.ownKickoffAt,
    this.partKickoffAt,
    this.sharedHeadCutId,
    this.sharedLabel,
    this.pay,
    this.worked = Duration.zero,
    this.ownDueRevisions = 0,
    this.partDueRevisions = 0,
    this.ownFirstDueAt,
    this.partFirstDueAt,
    this.ownWaitState,
    this.ownWaitReason,
    this.ownWaitUntil,
    this.partWaiting = false,
    this.partWaitReason,
    this.partWaitUntil,
    this.handedOffAt,
    this.handedOffNote,
    this.archived = false,
  });

  /// Put away (보관) — only in lists asked with `includeArchived`.
  final bool archived;

  /// Handed off to someone else (빠짐) — only in lists asked with
  /// `includeHandedOff`.
  final DateTime? handedOffAt;
  final String? handedOffNote;

  bool get handedOff => handedOffAt != null;

  final int id;
  final TaskStatus status;

  /// 1 for the first take, 2 for T2, …
  final int take;
  final int workId;
  final String workTitle;

  /// The work's client, if it has one, and the colour picked for it.
  final String? clientName;
  final int? clientColor;
  final String currency;
  final int episodeId;
  final String episodeNumber;
  final int stageId;
  final String stageName;

  /// The stage's place in its work's stage list (sort stages by this, not
  /// by id: ids follow when a stage was added, not where it stands).
  final int stagePosition;
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

  /// When production work began for this cut, if set (overrides the
  /// part's), and for the part × stage.
  final DateTime? ownKickoffAt;
  final DateTime? partKickoffAt;

  /// For a cut in a shared (겸용) group: the group's first cut, and the
  /// group's label (`C012-014`). Each cut keeps its own length and pay.
  final int? sharedHeadCutId;
  final String? sharedLabel;

  /// The production kickoff: the cut's own, else the part's.
  DateTime? get kickoffAt => ownKickoffAt ?? partKickoffAt;

  /// True when [kickoffAt] is the part's (the task set none).
  bool get kickoffFromPart => ownKickoffAt == null && partKickoffAt != null;

  /// Pay including paid retakes, or null when it cannot be computed yet.
  final int? pay;

  /// Timer time recorded on this task.
  final Duration worked;

  /// The deadline that applies: the task's own, else its part's.
  DateTime? get dueAt => ownDueAt ?? partDueAt;

  /// How many revisions the task's own deadline and its part's have
  /// (1st, 2nd … — see [CatalogueStore.extendDue]).
  final int ownDueRevisions;
  final int partDueRevisions;

  /// Revision 1 of each.
  final DateTime? ownFirstDueAt;
  final DateTime? partFirstDueAt;

  /// Which revision [dueAt] is: a cut's own deadline continues its part's
  /// (part 1st → the cut's own = 2nd), 0 with no deadline.
  int get dueRevision => dueAt == null
      ? 0
      : ownDueAt != null
      ? ownDueRevisions + (partId != null ? partDueRevisions : 0)
      : partDueRevisions;

  /// The first deadline ever given: the part's revision 1, else the task's.
  DateTime? get firstDueAt => partFirstDueAt ?? ownFirstDueAt ?? dueAt;

  /// Times the deadline was extended (revisions after the first).
  int get dueExtensions => dueRevision > 1 ? dueRevision - 1 : 0;

  /// The task's own waiting override: 1 waiting, 0 not, null = follow the
  /// part × stage.
  final int? ownWaitState;
  final String? ownWaitReason;
  final DateTime? ownWaitUntil;

  /// The part × stage is on hold.
  final bool partWaiting;
  final String? partWaitReason;
  final DateTime? partWaitUntil;

  /// On hold (대기): not yet workable — not counted as in hand, still
  /// counted in the daily pace (the deadline does not move).
  bool get waiting => ownWaitState == null ? partWaiting : ownWaitState == 1;

  /// True when [waiting] comes from the part × stage.
  bool get waitingFromPart => ownWaitState == null && partWaiting;

  /// Why, and until when it is expected (both optional).
  String? get waitReason =>
      ownWaitState == null ? partWaitReason : ownWaitReason;
  DateTime? get waitUntil =>
      ownWaitState == null ? partWaitUntil : ownWaitUntil;

  /// In the user's hands: open and not waiting.
  bool get inHand => status.isOpen && !waiting;

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
  /// Still in the user's hands: everything before the submission, done
  /// work included (the 「보유」 cuts).
  bool get isOpen => this != TaskStatus.submitted;

  /// Work still to do — what the daily pace counts (not done, not
  /// submitted).
  bool get needsWork =>
      this == TaskStatus.received ||
      this == TaskStatus.inProgress ||
      this == TaskStatus.retake;

  /// Handed to production: submitted.
  bool get isHanded => this == TaskStatus.submitted;

  /// Sort order when urgency matters: retake first, submitted last.
  int get urgency => switch (this) {
    TaskStatus.retake => 0,
    TaskStatus.inProgress => 1,
    TaskStatus.received => 2,
    TaskStatus.done => 3,
    TaskStatus.submitted => 4,
  };
}

/// The status of a group from its tasks' statuses: all submitted →
/// submitted; any retake → retake; all done or submitted → done; all
/// received → received; otherwise in progress.
TaskStatus deriveStatus(Map<TaskStatus, int> counts) {
  final total = counts.values.fold(0, (a, b) => a + b);
  int n(TaskStatus s) => counts[s] ?? 0;
  if (total == 0 || n(TaskStatus.received) == total) {
    return TaskStatus.received;
  }
  if (n(TaskStatus.submitted) == total) return TaskStatus.submitted;
  if (n(TaskStatus.retake) > 0) return TaskStatus.retake;
  if (n(TaskStatus.submitted) + n(TaskStatus.done) == total) {
    return TaskStatus.done;
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
/// Where a deadline lives: a part × stage, or one task's own (a cut's
/// override, a storyboard task).
class DueTarget {
  const DueTarget.part(int this.partId, int this.stageId) : taskId = null;
  const DueTarget.task(int this.taskId) : partId = null, stageId = null;

  final int? partId;
  final int? stageId;
  final int? taskId;

  @override
  bool operator ==(Object other) =>
      other is DueTarget &&
      other.partId == partId &&
      other.stageId == stageId &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(partId, stageId, taskId);
}

/// One revision of a deadline: 1 = the first, 2 = after one extension …
typedef DueRevision = ({int revision, DateTime dueAt, DateTime createdAt});

typedef PartStageRow = PartGroup;

/// A schedule unit: a part × stage with its cut tasks, the part-less cuts
/// of an episode × stage, or one storyboard task.
class PartGroup {
  PartGroup(this.tasks) : assert(tasks.isNotEmpty);

  /// The group's tasks, in cut order.
  final List<TaskRow> tasks;

  TaskRow get _first => tasks.first;
  String get key => _first.groupKey;

  /// Every task of the unit is put away (보관).
  bool get archived => tasks.every((t) => t.archived);

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
  int get stagePosition => _first.stagePosition;
  String? get clientName => _first.clientName;
  int? get clientColor => _first.clientColor;
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

  /// Cuts not handed in yet (done ones included) — the count at the right
  /// end of a timeline row.
  int get toSubmit => tasks.where((t) => t.status.isOpen).length;

  /// Open cuts in hand (not waiting) — the 「보유」 count.
  int get inHand => tasks.where((t) => t.inHand).length;

  /// Open cuts on hold.
  int get waiting => tasks.where((t) => t.status.isOpen && t.waiting).length;

  /// The part × stage itself is on hold (cuts may override).
  bool get partWaiting => _first.partWaiting;
  String? get partWaitReason => _first.partWaitReason;
  DateTime? get partWaitUntil => _first.partWaitUntil;

  /// Which revision the group's deadline is (1st, 2nd …), 0 with none.
  int get dueRevision => switch (kind) {
    GroupKind.part => _first.partDueAt == null ? 0 : _first.partDueRevisions,
    GroupKind.storyboard => _first.dueRevision,
    GroupKind.noPart => tasks.fold(
      0,
      (m, t) => t.dueRevision > m ? t.dueRevision : m,
    ),
  };

  /// The group's first deadline (revision 1).
  DateTime? get firstDueAt => switch (kind) {
    GroupKind.part => _first.partFirstDueAt ?? _first.partDueAt,
    GroupKind.storyboard => _first.firstDueAt,
    GroupKind.noPart => _earliest(tasks.map((t) => t.firstDueAt)),
  };

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
  /// The production kickoff: the part's; for a storyboard, its task's;
  /// for part-less cuts, the earliest.
  DateTime? get kickoffAt => switch (kind) {
    GroupKind.part => _first.partKickoffAt,
    GroupKind.storyboard => _first.kickoffAt,
    GroupKind.noPart => _earliest(tasks.map((t) => t.kickoffAt)),
  };

  /// The cut numbers as ranges ("C100~C103, C105"): the label of a
  /// part-less unit.
  String get cutsLabel => formatCutNumbers([
    for (final t in tasks)
      if (t.cutNumber != null) t.cutNumber!,
  ]);

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

/// Rolls [rows] (already in display order) into groups and sorts them:
/// groups in [manualOrder] (group key → position) first, in that order;
/// the rest by deadline, no deadline last; ties keep display order.
List<PartGroup> groupRows(
  Iterable<TaskRow> rows, {
  Map<String, int> manualOrder = const {},
}) {
  final byKey = <String, List<TaskRow>>{};
  for (final r in rows) {
    (byKey[r.groupKey] ??= []).add(r);
  }
  final groups = [for (final list in byKey.values) PartGroup(list)];
  final order = {for (var i = 0; i < groups.length; i++) groups[i]: i};
  groups.sort((a, b) {
    final ma = manualOrder[a.key];
    final mb = manualOrder[b.key];
    if (ma != null || mb != null) {
      if (ma == null) return 1;
      if (mb == null) return -1;
      if (ma != mb) return ma.compareTo(mb);
    }
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

/// Whether the (local) date [d] is a day off — the one judgment for every
/// count of working days: a rest weekday ([DateTime.weekday], 1 = Monday
/// … 7 = Sunday), a day in [daysOff], or a public holiday when
/// [isHoliday] is given (the user chose to rest on holidays).
bool isRestDay(
  DateTime d, {
  Set<int> restWeekdays = const {},
  Iterable<DaysOff> daysOff = const [],
  bool Function(DateTime date)? isHoliday,
}) =>
    restWeekdays.contains(d.weekday) ||
    daysOff.any((r) => r.contains(d)) ||
    (isHoliday?.call(d) ?? false);

/// The pace for [group] as of [now], or null when it has no end date.
/// Days count from the planned start (else the production kickoff) if
/// later than today, to the planned end (else the deadline) — or always
/// to the deadline with [PaceEnd.due].
/// Days off ([isRestDay]) are skipped when counting days.
Pace? paceFor(
  PartGroup group,
  DateTime now, {
  int dayStartMinutes = 0,
  Set<int> restWeekdays = const {},
  Iterable<DaysOff> daysOff = const [],
  bool Function(DateTime date)? isHoliday,
  PaceEnd endAt = PaceEnd.plan,
}) {
  bool off(DateTime d) => isRestDay(
    d,
    restWeekdays: restWeekdays,
    daysOff: daysOff,
    isHoliday: isHoliday,
  );

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
  // The user's own start; without one, when production work began.
  final planStart = group.planStartAt ?? group.kickoffAt;
  final startsLater = planStart != null && dateOf(planStart).isAfter(today);
  final from = startsLater ? dateOf(planStart) : today;
  final to = dateOf(endTime);
  var workDays = 0;
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    if (!off(d)) workDays++;
  }
  return Pace(
    remaining: group.tasks.where((t) => t.status.needsWork).length,
    workDays: workDays,
    startsLater: startsLater,
    end: endTime,
    restToday: off(today),
  );
}

/// One entry of the "today" list.
class TodayEntry {
  const TodayEntry({
    required this.group,
    required this.dueInDays,
    required this.pace,
    required this.beforePlan,
    required this.planStarted,
    this.due = const DueNone(),
    this.plan = const PlanNone(),
  });

  final PartGroup group;

  /// Deadline signal ([dueSignal]).
  final DueSignal due;

  /// Plan signal ([planSignal]) against the stage's recent average.
  final PlanSignal plan;

  /// Days left to the deadline; negative = late; null = no deadline.
  final int? dueInDays;

  /// Cuts per day needed, or null without an end date.
  final Pace? pace;

  /// The planned start is after today: show dimmed ("starts 12/7").
  final bool beforePlan;

  /// The planned start has come (even if the planned end has passed).
  final bool planStarted;
}

/// The "today" view: its entries, the late count and today's cut total.
class TodayView {
  const TodayView({
    required this.entries,
    required this.late,
    required this.cutsToday,
  });

  static const empty = TodayView(entries: [], late: 0, cutsToday: 0);

  final List<TodayEntry> entries;

  /// Late open groups plus late open cuts with their own deadline.
  final int late;

  /// What every open group asks of today, summed.
  final double cutsToday;
}

/// The user's usual speed for one stage name (LO, 원화 …): cuts handed over
/// in the recent window divided by the working days in it.
class UsualPace {
  const UsualPace({
    required this.stageName,
    required this.cuts,
    required this.workDays,
  });

  final String stageName;
  final int cuts;
  final int workDays;

  /// Cuts per working day, or null with no working day in the window.
  double? get perDay => workDays == 0 ? null : cuts / workDays;
}

/// How a needed pace compares with the usual one.
enum PaceLevel {
  /// No usual pace to compare with (no history yet).
  unknown,

  /// At or below the usual pace.
  ok,

  /// Above the usual pace (yellow).
  tight,

  /// Above 1.5 × the usual pace (red).
  over,
}

/// Compares a [needed] cuts-per-day with the [usual] one: above usual is
/// [PaceLevel.tight], above 1.5 × usual is [PaceLevel.over]. Behind
/// (no working day left with cuts remaining) is always over.
PaceLevel paceLevel(Pace pace, double? usual) {
  if (pace.behind) return PaceLevel.over;
  final needed = pace.perDay;
  if (needed == null || pace.remaining == 0) return PaceLevel.ok;
  if (usual == null || usual <= 0) return PaceLevel.unknown;
  if (needed > usual * 1.5) return PaceLevel.over;
  if (needed > usual) return PaceLevel.tight;
  return PaceLevel.ok;
}

/// Working days in local `[from, to]` (both dates included), skipping
/// days off ([isRestDay]).
int workDaysBetween(
  DateTime from,
  DateTime to, {
  Set<int> restWeekdays = const {},
  Iterable<DaysOff> daysOff = const [],
  bool Function(DateTime date)? isHoliday,
}) {
  var n = 0;
  for (
    var d = DateTime.utc(from.year, from.month, from.day);
    !d.isAfter(DateTime.utc(to.year, to.month, to.day));
    d = d.add(const Duration(days: 1))
  ) {
    if (!isRestDay(
      d,
      restWeekdays: restWeekdays,
      daysOff: daysOff,
      isHoliday: isHoliday,
    )) {
      n++;
    }
  }
  return n;
}

/// A stage's speeds: recent (the last weeks, a setting) and overall
/// (since its first handed-over cut).
class StagePace {
  const StagePace({
    required this.stageName,
    required this.recent,
    required this.overall,
  });

  final String stageName;
  final UsualPace recent;
  final UsualPace overall;
}

/// The deadline signal: only the production deadline counts here — never
/// the user's plan or pace. D-n and days late always come from `dueAt`.
sealed class DueSignal {
  const DueSignal();
}

/// Every cut's work is done, not all submitted yet: the deadline (for the
/// submission) still runs — [daysLeft] to it (negative = late), null with
/// none.
final class DueDone extends DueSignal {
  const DueDone([this.daysLeft]);

  final int? daysLeft;
}

/// Every cut is submitted — out of the user's hands.
final class DueSubmitted extends DueSignal {
  const DueSubmitted();
}

/// No deadline set.
final class DueNone extends DueSignal {
  const DueNone();
}

/// Past the deadline by [days] (≥ 1).
final class DueLate extends DueSignal {
  const DueLate(this.days);

  final int days;
}

/// [days] left to the deadline (0 = due today).
final class DueDaysLeft extends DueSignal {
  const DueDaysLeft(this.days);

  final int days;
}

/// The deadline signal for [group] as of [now].
DueSignal dueSignal(
  PartGroup group, {
  required DateTime now,
  int dayStartMinutes = 0,
}) {
  switch (group.status) {
    case TaskStatus.submitted:
      return const DueSubmitted();
    case TaskStatus.done:
      final due = group.dueAt;
      return DueDone(due == null ? null : dueInDays(due, now, dayStartMinutes));
    case TaskStatus.received:
    case TaskStatus.inProgress:
    case TaskStatus.retake:
      break;
  }
  final due = group.dueAt;
  if (due == null) return const DueNone();
  final days = dueInDays(due, now, dayStartMinutes);
  return days < 0 ? DueLate(-days) : DueDaysLeft(days);
}

/// The plan signal: how the user's own plan and pace look. Separate from
/// [DueSignal] by design.
sealed class PlanSignal {
  const PlanSignal();
}

/// Nothing to flag (or the unit is out of the user's hands).
final class PlanNone extends PlanSignal {
  const PlanNone();
}

/// The planned finish is after the deadline.
final class PlanOver extends PlanSignal {
  const PlanOver();
}

/// The planned start has come, but nothing has been started.
final class PlanLateStart extends PlanSignal {
  const PlanLateStart();
}

/// The needed pace is above 1.5 × the recent average (or no working day
/// is left).
final class PlanHard extends PlanSignal {
  const PlanHard();
}

/// The needed pace is above the recent average.
final class PlanTight extends PlanSignal {
  const PlanTight();
}

/// The planned start is later than today.
final class PlanNotStarted extends PlanSignal {
  const PlanNotStarted(this.startAt);

  final DateTime startAt;
}

/// The plan signal for [group] as of [now]. [pace] is the group's needed
/// pace ([paceFor]); [recentPerDay] is the recent average for its stage.
/// Priority: over > late start > hard > tight > not started.
PlanSignal planSignal(
  PartGroup group, {
  required DateTime now,
  int dayStartMinutes = 0,
  Pace? pace,
  double? recentPerDay,
}) {
  final status = group.status;
  if (!status.needsWork) return const PlanNone();
  final slack = group.slackDays;
  if (slack != null && slack < 0) return const PlanOver();
  final start = group.planStartAt;
  final toStart = start == null ? null : dueInDays(start, now, dayStartMinutes);
  if (toStart != null && toStart <= 0 && status == TaskStatus.received) {
    return const PlanLateStart();
  }
  if (pace != null) {
    switch (paceLevel(pace, recentPerDay)) {
      case PaceLevel.over:
        return const PlanHard();
      case PaceLevel.tight:
        return const PlanTight();
      case PaceLevel.ok:
      case PaceLevel.unknown:
        break;
    }
  }
  if (start != null && toStart != null && toStart > 0) {
    return PlanNotStarted(start);
  }
  return const PlanNone();
}

/// Both signals and the needed pace for one group, as the views show them.
class GroupSignals {
  const GroupSignals({required this.due, required this.plan, this.pace});

  final DueSignal due;
  final PlanSignal plan;
  final Pace? pace;
}
