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

  /// Pay including paid retakes, or null when it cannot be computed yet.
  final int? pay;

  /// Timer time recorded on this task.
  final Duration worked;

  DateTime? get dueAt => ownDueAt ?? partDueAt;

  /// True when a cut in a part carries its own deadline.
  bool get dueOverridden => partId != null && ownDueAt != null;

  bool get isOpen => status.isOpen;

  /// The rows that make one schedule unit share this key: a part × stage,
  /// or the task alone (a storyboard, or a cut outside any part).
  String get groupKey => partId == null ? 'task:$id' : 'part:$partId:$stageId';
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

/// A schedule unit: a part × stage with its cut tasks, or one solo task.
class PartGroup {
  PartGroup(this.tasks) : assert(tasks.isNotEmpty);

  /// The group's tasks, in cut order.
  final List<TaskRow> tasks;

  TaskRow get _first => tasks.first;
  String get key => _first.groupKey;
  bool get solo => _first.partId == null;
  int get workId => _first.workId;
  String get workTitle => _first.workTitle;
  String get currency => _first.currency;
  String get episodeNumber => _first.episodeNumber;
  int get stageId => _first.stageId;
  String get stageName => _first.stageName;
  int? get partId => _first.partId;
  int? get plannedCutCount => _first.plannedCutCount;

  /// Part label, or the storyboard label / cut number of a solo task.
  String get label =>
      _first.partLabel ?? _first.storyboardLabel ?? _first.cutNumber ?? '';

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

  /// The part's deadline for the stage, or the solo task's deadline.
  DateTime? get dueAt => solo ? _first.dueAt : _first.partDueAt;

  /// When the earliest task arrived.
  DateTime? get startAt {
    DateTime? s;
    for (final t in tasks) {
      final r = t.receivedAt;
      if (r != null && (s == null || r.isBefore(s))) s = r;
    }
    return s;
  }

  /// Sum of computable pay, in [currency].
  int get pay => tasks.fold(0, (a, t) => a + (t.pay ?? 0));

  /// Tasks whose pay cannot be computed yet.
  int get unpriced => tasks.where((t) => t.pay == null).length;

  Duration get worked => tasks.fold(Duration.zero, (a, t) => a + t.worked);
}

/// Rolls [rows] (already in display order) into groups, keeping the order
/// in which each group first appears.
List<PartGroup> groupRows(Iterable<TaskRow> rows) {
  final byKey = <String, List<TaskRow>>{};
  for (final r in rows) {
    (byKey[r.groupKey] ??= []).add(r);
  }
  return [for (final list in byKey.values) PartGroup(list)];
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
