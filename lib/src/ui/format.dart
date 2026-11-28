/// Words and number formats the views show. UI-only: the data lane's
/// models stay free of display strings.
library;

import '../models/catalogue.dart';
import '../models/progress.dart';
import 'text/strings.dart';

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
    TaskStatus.received => S.stReceived.t,
    TaskStatus.inProgress => S.stInProgress.t,
    TaskStatus.submitted => S.stSubmitted.t,
    TaskStatus.retake => S.stRetake.t,
    TaskStatus.done => S.stDone.t,
  };
}

/// How a deadline label looks: only a missed deadline stands out.
enum DueTone { none, quiet, late }

/// The production deadline as one short label as of [now]: 「D-3」,
/// 「D-day」, or 「2일 지남」 once it has passed. The user's own plan never
/// changes this label. Handed-over work never looks late.
({String text, DueTone tone}) dueLabel(
  DateTime? dueAt,
  DateTime now,
  TaskStatus status, {
  int dayStartMinutes = 0,
}) => dueLabelFromDays(
  dueAt == null ? null : dueInDays(dueAt, now, dayStartMinutes),
  status,
);

/// [dueLabel] from days already counted (negative = late, null = none).
({String text, DueTone tone}) dueLabelFromDays(int? days, TaskStatus status) {
  // Handed in: no deadline to watch any more. Done but not handed in still
  // counts down — it has yet to go.
  if (days == null || status.isHanded) {
    return (text: '—', tone: DueTone.none);
  }
  final text = days < 0
      ? S.daysLate.f({'n': -days})
      : (days == 0 ? 'D-day' : 'D-$days');
  final late = days < 0 && status.isOpen;
  return (text: text, tone: late ? DueTone.late : DueTone.quiet);
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

/// 「11/28(토)」 in local time.
String formatDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  final wd = weekdayNames()[l.weekday - 1];
  return switch (appLang.value) {
    Lang.fr => '${l.day}/${l.month} $wd',
    Lang.en => '${l.month}/${l.day} $wd',
    _ => '${l.month}/${l.day}($wd)',
  };
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
///
/// Every screen names a unit through this one function. A part-less unit
/// reads as its cut range (C001~C050, C060~C102) — 「파트 없음」 told
/// nothing (v8).
String groupTitle(PartGroup g) => switch (g.kind) {
  GroupKind.part => S.partTitle.f({'p': g.partLabel}),
  GroupKind.noPart => g.cutsLabel.isEmpty ? S.noPart.t : g.cutsLabel,
  GroupKind.storyboard => g.storyboardLabel ?? S.storyboard.t,
};

/// 「4컷」 for cuts, 「1건」 for a storyboard.
String groupCount(PartGroup g) =>
    g.kind == GroupKind.storyboard ? S.items.f({'n': 1}) : '${g.total} cut';

/// An episode as the screens show it: a number gets a 「#」 (#07), the way
/// a cut gets its C; a name (극장판, MV) stays as it is. Display only — the
/// stored number has no 「#」.
String episodeLabel(String number) {
  final n = number.trim();
  return RegExp(r'^\d+$').hasMatch(n) ? '#$n' : n;
}

/// What to store for an episode the user typed: 「#07」 is 07.
String episodeNumberOf(String typed) {
  final n = typed.trim();
  return RegExp(r'^#\d+$').hasMatch(n) ? n.substring(1) : n;
}

/// A task's own name: its cut number or storyboard label.
String taskLabel(TaskRow t) => t.cutNumber ?? t.storyboardLabel ?? '';

/// The deadline signal as one label; only [DueLate] stands out.
({String text, bool late, bool quiet}) dueSignalLabel(DueSignal s) =>
    switch (s) {
      DueDone() => (text: S.stDone.t, late: false, quiet: true),
      DueSubmitted() => (text: S.stSubmitted.t, late: false, quiet: true),
      DueNone() => (text: '—', late: false, quiet: true),
      DueLate(:final days) => (
        text: S.daysLate.f({'n': days}),
        late: true,
        quiet: false,
      ),
      DueDaysLeft(:final days) => (
        text: days == 0 ? 'D-day' : 'D-$days',
        late: false,
        quiet: false,
      ),
    };

/// How loud a plan signal is: a red or yellow dot, or nothing.
enum PlanTone { none, amber, red }

PlanTone planTone(PlanSignal s) => switch (s) {
  PlanOver() || PlanHard() => PlanTone.red,
  PlanLateStart() || PlanTight() => PlanTone.amber,
  PlanNotStarted() || PlanNone() => PlanTone.none,
};

/// Why the plan dot shows, for the opened details; null when it does not.
String? planReason(PlanSignal s) => switch (s) {
  PlanOver() => S.planOver.t,
  PlanHard() => S.planHard.t,
  PlanLateStart() => S.planLateStart.t,
  PlanTight() => S.planTight.t,
  PlanNotStarted() || PlanNone() => null,
};
