/// Read model for the four views: the user's tasks grouped by part × stage.
///
/// Pure Dart. The data lane's catalogue fills it; until its read API lands,
/// `sample_overview.dart` stands in.
library;

import '../models/catalogue.dart';

/// One task as the views show it: one stage of one cut (or a storyboard).
class TaskItem {
  const TaskItem({
    required this.id,
    required this.label,
    required this.status,
    this.lengthMs,
    this.take = 1,
    this.dueAt,
    this.dueFromPart = true,
    this.pay,
    this.worked = Duration.zero,
  });

  final int id;

  /// Cut number, or the storyboard's label.
  final String label;
  final int? lengthMs;
  final TaskStatus status;

  /// 1 for the first take; 2, 3, … after retakes.
  final int take;
  final DateTime? dueAt;

  /// False when the task carries its own deadline instead of its part's.
  final bool dueFromPart;

  /// Pay in the currency's smallest unit, or null while it cannot be priced.
  final int? pay;
  final Duration worked;

  bool get isOpen => status.isOpen;
}

/// A bundle the schedule is planned by: one stage of one part of an
/// episode, e.g. 「별빛 정류장 #07 · B파트 · 원화」.
class PartStage {
  PartStage({
    required this.key,
    required this.workTitle,
    required this.currency,
    required this.episode,
    required this.stage,
    required this.tasks,
    this.partLabel,
    this.dueAt,
    this.plannedCount,
    this.isStoryboard = false,
  });

  /// Stable identity across reloads (for selection and expansion).
  final String key;
  final String workTitle;

  /// ISO 4217 code, e.g. JPY.
  final String currency;
  final String episode;

  /// Part label such as 「B」; null for cuts outside any part.
  final String? partLabel;
  final String stage;
  final DateTime? dueAt;
  final int? plannedCount;
  final bool isStoryboard;
  final List<TaskItem> tasks;

  late final TaskStatus status = partStatus([for (final t in tasks) t.status]);

  /// Tasks submitted or done.
  late final int handedIn = tasks
      .where(
        (t) => t.status == TaskStatus.submitted || t.status == TaskStatus.done,
      )
      .length;

  late final int payTotal = tasks.fold(0, (a, t) => a + (t.pay ?? 0));
  late final int unpriced = tasks.where((t) => t.pay == null).length;
  late final Duration worked = tasks.fold(
    Duration.zero,
    (a, t) => a + t.worked,
  );

  int count(TaskStatus s) => tasks.where((t) => t.status == s).length;

  bool get isOpen => status.isOpen;
}

extension TaskStatusView on TaskStatus {
  String get label => switch (this) {
    TaskStatus.received => '받음',
    TaskStatus.inProgress => '작업중',
    TaskStatus.submitted => '제출',
    TaskStatus.retake => '리테이크',
    TaskStatus.done => '완료',
  };

  /// Still on the user's desk: not handed in.
  bool get isOpen =>
      this == TaskStatus.received ||
      this == TaskStatus.inProgress ||
      this == TaskStatus.retake;
}

/// A part's status from its tasks' (provisional rule, mock-up v4):
/// all done → done; any retake → retake; all handed in → submitted;
/// all received → received; otherwise in progress.
TaskStatus partStatus(List<TaskStatus> s) {
  if (s.isEmpty) return TaskStatus.received;
  bool all(bool Function(TaskStatus) f) => s.every(f);
  if (all((x) => x == TaskStatus.done)) return TaskStatus.done;
  if (s.contains(TaskStatus.retake)) return TaskStatus.retake;
  if (all((x) => x == TaskStatus.submitted || x == TaskStatus.done)) {
    return TaskStatus.submitted;
  }
  if (all((x) => x == TaskStatus.received)) return TaskStatus.received;
  return TaskStatus.inProgress;
}

/// How urgent a deadline looks.
enum DueTone { none, quiet, soon, late }

/// The short D-day label for a deadline as of [today] (a local date), e.g.
/// 「D-3」, 「D-day」, 「+2」(two days late). Handed-in work never looks urgent.
({String text, DueTone tone}) dueLabel(
  DateTime? dueAt,
  DateTime today,
  TaskStatus status,
) {
  if (dueAt == null || status == TaskStatus.done) {
    return (text: '—', tone: DueTone.none);
  }
  final d = dueAt.toLocal();
  final days = DateTime(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
  final text = days < 0 ? '+${-days}' : (days == 0 ? 'D-day' : 'D-$days');
  if (!status.isOpen) return (text: text, tone: DueTone.quiet);
  final tone = days <= 0
      ? DueTone.late
      : (days <= 2 ? DueTone.soon : DueTone.quiet);
  return (text: text, tone: tone);
}

/// Cut length as 「초+코마」 at 24 frames a second, e.g. 3+12.
String formatLength(int? ms) {
  if (ms == null) return '—';
  final frames = (ms * 24 + 500) ~/ 1000;
  return '${frames ~/ 24}+${(frames % 24).toString().padLeft(2, '0')}';
}

/// 「4:30」 style hours and minutes.
String formatWorked(Duration d) =>
    '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';

/// Money with its currency sign and thousands separators: ¥4,500, ₩900,000.
String formatMoney(String currency, int amount) {
  final sign = switch (currency) {
    'JPY' => '¥',
    'KRW' => '₩',
    'USD' => r'$',
    _ => '$currency ',
  };
  final digits = amount.abs().toString();
  final b = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return '$sign$b';
}

/// Sum of pay per currency, in first-seen order. No conversion.
Map<String, int> totalsByCurrency(Iterable<PartStage> parts) {
  final out = <String, int>{};
  for (final p in parts) {
    out[p.currency] = (out[p.currency] ?? 0) + p.payTotal;
  }
  return out;
}
