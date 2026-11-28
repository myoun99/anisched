/// Words and number formats the views show. UI-only: the data lane's
/// models stay free of display strings.
library;

import 'package:flutter/foundation.dart';

import '../models/catalogue.dart';
import '../models/progress.dart';
import '../models/number_style.dart';
import '../models/stage_names.dart';
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

/// The small line under a unit's name: its part and cut range (「A파트 ·
/// C012~C021」); a part-less unit's cut range alone; a storyboard's label.
String partCutsLine(PartGroup g) => switch (g.kind) {
  GroupKind.part =>
    g.cutsLabel.isEmpty ? groupTitle(g) : '${groupTitle(g)} · ${g.cutsLabel}',
  GroupKind.noPart => g.cutsLabel,
  GroupKind.storyboard => groupTitle(g),
};

/// What is left to work on: 「3 cut」, or 「1건」 for a storyboard.
String cutsLeftLabel(PartGroup g) {
  final n = g.tasks.where((t) => t.status.needsWork).length;
  return g.kind == GroupKind.storyboard ? S.items.f({'n': n}) : '$n cut';
}

/// 「4컷」 for cuts, 「1건」 for a storyboard.
String groupCount(PartGroup g) =>
    g.kind == GroupKind.storyboard ? S.items.f({'n': 1}) : '${g.total} cut';

/// The document's episode style (#·2 by default), kept current by the
/// shell; [episodeShown] reads it.
final episodeStyle = ValueNotifier<NumberStyle>(defaultEpisodeStyle);

/// How an episode number the user is typing will read once stored (「7」
/// → 「#07」; a name such as 「SP」 as typed). The store keeps the value.
String episodeShown(String typed) =>
    shownNumber(storedNumber(typed, episodeStyle.value), episodeStyle.value);

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

/// A stage as the screens show it, in the user's language — Anicel's own
/// short names for the work and checker axes (原画/作監, KEY/AD, 원화/작감);
/// a name the user typed stays as typed. The one place a stage is named.
String stageText(String stored) {
  final l = stageLabelOf(stored);
  if (l == null) return stored;
  final lang = appLang.value;
  if (l.extra case final e?) {
    return switch (e) {
      StageExtra.retake => S.stRetake.t,
      StageExtra.characterDesign => S.charDesign.t,
    };
  }
  final work = _stageWords[l.work!]![lang.index];
  final check = l.check;
  return check == null ? work : '$work/${_checkWords[check]![lang.index]}';
}

// Anicel's `layerProcessAbbrev` / `layerReviseAbbrev`, in Lang order
// (en, ja, ko, fr, zh-Hans).
const _stageWords = {
  StageWork.conte: ['SB', 'コンテ', '콘티', 'SB', '分镜'],
  StageWork.layout: ['LO', 'LO', 'LO', 'LO', 'LO'],
  StageWork.roughKey: ['RK', 'ラフ原', '러프원', 'RK', '粗原'],
  StageWork.key: ['KEY', '原画', '원화', 'KEY', '原画'],
  StageWork.inbetween: ['IB', '動画', '동화', 'IB', '中割'],
  StageWork.finish: ['FIN', '仕上', '시아게', 'FIN', '上色'],
};

const _checkWords = {
  StageCheck.direction: ['DIR', '演出', '연출', 'DIR', '演出'],
  StageCheck.animationDirector: ['AD', '作監', '작감', 'AD', '作监'],
  StageCheck.chiefAnimationDirector: ['CAD', '総作監', '총작감', 'CAD', '总作监'],
  StageCheck.director: ['DR', '監督', '감독', 'DR', '导演'],
  StageCheck.chiefDirector: ['CD', '総監督', '총감독', 'CD', '总导演'],
  StageCheck.actionAnimationDirector: ['AAD', 'アク作', '액션', 'AAD', '动作'],
  StageCheck.inbetweenCheck: ['IBC', '動検', '동검', 'IBC', '中检'],
  StageCheck.cellCheck: ['CC', 'セル検', '셀검', 'CC', '赛检'],
};
