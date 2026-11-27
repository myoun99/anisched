/// Words and number formats the views show. UI-only: the data lane's
/// models stay free of display strings.
library;

import '../models/catalogue.dart';
import '../models/progress.dart';

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
    TaskStatus.received => '받음',
    TaskStatus.inProgress => '작업중',
    TaskStatus.submitted => '제출',
    TaskStatus.retake => '리테이크',
    TaskStatus.done => '완료',
  };
}

/// How urgent a deadline looks.
enum DueTone { none, quiet, soon, late }

/// The short D-day label for a deadline as of [now], e.g. 「D-3」,
/// 「D-day」, 「+2」 (two days late). Handed-over work never looks urgent.
({String text, DueTone tone}) dueLabel(
  DateTime? dueAt,
  DateTime now,
  TaskStatus status, {
  int dayStartMinutes = 0,
}) {
  if (dueAt == null || status == TaskStatus.done) {
    return (text: '—', tone: DueTone.none);
  }
  final days = dueInDays(dueAt, now, dayStartMinutes);
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

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 「11/28(토)」 in local time.
String formatDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.month}/${l.day}(${_weekdays[l.weekday - 1]})';
}

/// Sum of pay per currency, in first-seen order. No conversion.
Map<String, int> totalsByCurrency(Iterable<PartGroup> groups) {
  final out = <String, int>{};
  for (final g in groups) {
    out[g.currency] = (out[g.currency] ?? 0) + g.pay;
  }
  return out;
}

/// 「B파트」, 「파트 없음」 for an episode's loose cuts, or a storyboard's label.
String groupTitle(PartGroup g) => switch (g.kind) {
  GroupKind.part => '${g.partLabel}파트',
  GroupKind.noPart => '파트 없음',
  GroupKind.storyboard => g.storyboardLabel ?? '콘티',
};

/// 「4컷」 for cuts, 「1건」 for a storyboard.
String groupCount(PartGroup g) =>
    g.kind == GroupKind.storyboard ? '1건' : '${g.total}컷';

/// A task's own name: its cut number or storyboard label.
String taskLabel(TaskRow t) => t.cutNumber ?? t.storyboardLabel ?? '';
