/// Shared pieces for views that list part × stage groups: a header, a
/// one-line summary and the details that open under it.
library;

import 'package:flutter/material.dart';

import '../controllers/unit_bundles.dart';
import '../models/progress.dart';
import 'due_button.dart';
import 'fit_text.dart';
import 'fold.dart';
import 'hold.dart';
import 'format.dart';
import 'selection.dart';
import 'theme.dart';
import 'widgets.dart';
import 'text/strings.dart';

const caretW = 32.0;
const _progressW = 112.0;
const _signalW = 100.0;
const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

class PartHeader extends StatelessWidget {
  const PartHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextStyle(fontSize: 12, color: c.muted);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            const SizedBox(width: caretW),
            Expanded(child: Text(S.part.t, style: style)),
            SizedBox(
              width: _progressW,
              child: Text(S.progress.t, style: style),
            ),
            SizedBox(
              width: _signalW,
              child: Text(S.due.t, style: style, textAlign: TextAlign.right),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

/// Name, progress and the date signal for one group. Tapping opens it.
/// How a bundle line shows its stages' progress — two proposals until
/// the user picks one.
enum BundleProgress {
  /// One thin bar per stage, stacked.
  perStage,

  /// One bar of every stage's cuts together.
  sum,
}

/// The proposal in use (captures switch it).
BundleProgress bundleProgress = BundleProgress.perStage;

class PartLine extends StatelessWidget {
  const PartLine({
    super.key,
    required this.group,
    this.bundle,
    required this.now,
    required this.dayStartMinutes,
    required this.expanded,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
    this.signal,
    this.signals,
    this.picked = Picked.none,
    this.onLongPress,
    this.onDue,
  });

  /// Sets the unit's deadline (tap on the D label); null keeps it fixed.
  final ValueChanged<DateTime>? onDue;

  /// The unit (for a bundle, its [UnitBundle.lead]: the D shown).
  final PartGroup group;

  /// Several stages of the same cuts on one line (「LO・原画」); null or
  /// single for a plain unit's line.
  final UnitBundle? bundle;
  final DateTime now;
  final int dayStartMinutes;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  /// Fades the line (work whose planned start is still ahead).
  final bool dimmed;

  /// Replaces the deadline label, e.g. one built from precomputed days.
  final Widget? signal;

  /// The group's deadline and plan signals; when given they fill the D
  /// slot and a plan that has not started dims the line.
  final GroupSignals? signals;

  /// How much of the group is picked for an action (fill colour only).
  final Picked picked;

  /// Picks or drops the whole group.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final b = bundle == null || bundle!.single ? null : bundle;
    final fill = switch (picked) {
      Picked.all => c.selected,
      Picked.some => Color.lerp(c.panel, c.selected, 0.5)!,
      Picked.none => selected ? c.hover : c.panel,
    };
    final line = Material(
      color: fill,
      child: InkWell(
        key: Key('line-${b?.key ?? g.key}'),
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: c.hover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            height: 52,
            child: DefaultTextStyle.merge(
              style: _tabular,
              child: Row(
                children: [
                  SizedBox(
                    width: caretW,
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: c.muted,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        // The line's long press picks it: no tooltips here;
                        // the opened details show every word.
                        FitText.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: groupTitle(g),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (b == null)
                                TextSpan(
                                  text: '  ${stageText(g.stageName)}',
                                  style: TextStyle(color: c.muted),
                                )
                              else ...[
                                const TextSpan(text: '  '),
                                // The stage whose D is shown reads darker.
                                for (final (i, s) in b.stages.indexed)
                                  TextSpan(
                                    text:
                                        '${i == 0 ? '' : '・'}'
                                        '${stageText(s.stageName)}',
                                    style: TextStyle(
                                      color: s == g ? null : c.muted,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                          tooltip: false,
                        ),
                        FitText(
                          '${g.workTitle} ${episodeLabel(g.episodeNumber)}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                          tooltip: false,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _progressW,
                    child: Row(
                      spacing: 5,
                      children: [
                        SizedBox(width: 40, child: _progress(b)),
                        Flexible(
                          child: Text(
                            b == null
                                ? '${g.handed}/${g.total}'
                                : '${b.handed}/${b.total}',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ),
                        if (_waiting(b) > 0)
                          HoldMark(
                            key: Key('hold-mark-${b?.key ?? g.key}'),
                            count: _waiting(b),
                          ),
                      ],
                    ),
                  ),
                  // Only the D label opens the date picker; the rest of the
                  // slot belongs to the line (open / pick).
                  SizedBox(
                    width: _signalW,
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: DueButton(
                        key: Key('due-${g.key}'),
                        title: S.pickDue.t,
                        due: g.dueAt,
                        onPicked: onDue,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child:
                                      signal ??
                                      (signals == null
                                          ? null
                                          : SignalLabel(
                                              due: signals!.due,
                                              plan: signals!.plan,
                                            )) ??
                                      DueText(
                                        g.dueAt,
                                        g.status,
                                        now,
                                        dayStartMinutes: dayStartMinutes,
                                      ),
                                ),
                              ),
                              RoundBadge(g.dueRevision),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final fade =
        dimmed ||
        (g.waiting > 0 && g.inHand == 0) ||
        g.tasks.every((t) => t.handedOff) ||
        (signals?.plan is PlanNotStarted &&
            planTone(signals!.plan) == PlanTone.none);
    return fade ? Opacity(opacity: 0.5, child: line) : line;
  }

  int _waiting(UnitBundle? b) =>
      b == null ? group.waiting : b.stages.fold(0, (n, s) => n + s.waiting);

  Widget _progress(UnitBundle? b) {
    if (b == null) return PartProgress(group, height: 4);
    return switch (bundleProgress) {
      BundleProgress.perStage => Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [for (final s in b.stages) PartProgress(s, height: 3)],
      ),
      BundleProgress.sum => PartProgress(b.together, height: 4),
    };
  }
}

/// What opens under a line: dates, plan, pace, pay, time and the cuts.
class PartDetails extends StatelessWidget {
  const PartDetails({
    super.key,
    required this.group,
    this.pace,
    this.extra = const [],
    this.highlighted,
    this.onTask,
    this.plan,
    this.usual,
    this.isPicked,
    this.onDue,
    this.onTaskLongPress,
    this.onKickoff,
    this.onPlanStart,
    this.onPlanEnd,
    this.onHold,
    this.loadRevisions,
    this.onEditRevision,
  });

  /// Puts the whole unit on hold or takes it off; null hides the button.
  final VoidCallback? onHold;

  /// The deadline's rounds, for the folded 「마감 차수」 list; null hides it.
  final Future<List<DueRevision>> Function()? loadRevisions;

  /// Corrects one round of the deadline.
  final void Function(int revision, DateTime due)? onEditRevision;

  final PartGroup group;
  final Pace? pace;

  /// More label/value pairs after the standard ones.
  final List<(String, String)> extra;

  /// A task to mark (e.g. the one the timer runs on).
  final int? highlighted;

  /// Tapping a cut, when the view wants it (e.g. to start the timer).
  final ValueChanged<TaskRow>? onTask;

  /// The plan signal; its reason shows as one line.
  final PlanSignal? plan;

  /// The stage's usual speeds (overall · recent).
  final StagePace? usual;

  /// Whether a cut is picked for an action (filled like the highlight).
  final bool Function(TaskRow task)? isPicked;

  /// Sets the unit's deadline (tap on the 마감 fact).
  final ValueChanged<DateTime>? onDue;

  /// Sets the production start (착수); null keeps it fixed.
  final ValueChanged<DateTime>? onKickoff;

  /// Sets the user's own work start and end.
  final ValueChanged<DateTime>? onPlanStart;
  final ValueChanged<DateTime>? onPlanEnd;

  /// Long press on a cut: picks it for the bar's actions.
  final ValueChanged<TaskRow>? onTaskLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final slack = g.slackDays;
    final perDay = pace?.perDay;
    // Each date is its own button, titled with what it picks.
    Widget date(
      String key,
      DateTime? d,
      ValueChanged<DateTime>? onPicked,
      String title, {
      String empty = '—',
    }) => DueButton(
      key: Key('$key-${g.key}'),
      title: title,
      due: d,
      onPicked: onPicked,
      child: Text(
        d == null ? empty : formatDate(d),
        style: onPicked == null
            ? null
            : TextStyle(
                decoration: TextDecoration.underline,
                decorationColor: c.faint,
              ),
      ),
    );
    Widget fact(String label, List<Widget> value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label  ', style: TextStyle(fontSize: 12, color: c.muted)),
        ...value,
      ],
    );
    const dash = Text(' – ');
    final dates = [
      fact(S.due.t, [
        date('details-due', g.dueAt, onDue, S.pickDue.t),
        RoundBadge(g.dueRevision),
      ]),
      fact(S.production.t, [
        date('details-kickoff', g.kickoffAt, onKickoff, S.pickKickoff.t),
        dash,
        Text(formatDate(g.dueAt)),
      ]),
      fact(S.ownWork.t, [
        date(
          'details-plan-start',
          g.planStartAt,
          onPlanStart,
          S.pickPlanStart.t,
        ),
        dash,
        date(
          'details-plan-end',
          g.planEndAt,
          onPlanEnd,
          S.pickPlanEnd.t,
          empty: S.due.t,
        ),
      ]),
    ];
    final facts = <(String, String)>[
      (S.slack.t, slack == null ? '—' : S.days.f({'n': slack})),
      (S.perDay.t, perDay == null ? '—' : '${perDay.toStringAsFixed(1)} cut'),
      (S.rate.t, formatMoney(g.currency, g.pay)),
      (S.time.t, formatWorked(g.worked)),
      if (usual != null)
        (
          S.usual.t,
          '${_perDay(usual!.overall)} · ${S.recent.t} ${_perDay(usual!.recent)}',
        ),
      if (plan case PlanNotStarted(:final startAt)) ('IN', formatDate(startAt)),
      ...extra,
    ];
    final reason = plan == null ? null : planReason(plan!);
    final reasonColor = plan == null
        ? null
        : switch (planTone(plan!)) {
            PlanTone.red => c.retake,
            PlanTone.amber => c.submitted,
            PlanTone.none => c.muted,
          };
    return DecoratedBox(
      key: Key('details-${g.key}'),
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(caretW, 10, 14, 12),
        child: DefaultTextStyle.merge(
          style: _tabular,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              _holdRow(context),
              Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  ...dates,
                  for (final (k, v) in facts)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$k  ',
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                          TextSpan(text: v),
                        ],
                      ),
                    ),
                ],
              ),
              if (loadRevisions != null && g.dueAt != null) ...[
                FoldToggle(
                  key: Key('fold-rounds-${g.key}'),
                  state: Folds.dueRounds,
                  label: S.dueRounds.t,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: Folds.dueRounds,
                  builder: (context, open, _) => !open
                      ? const SizedBox.shrink()
                      : DueRevisionList(
                          load: loadRevisions!,
                          current: g.dueAt,
                          onEdit: onEditRevision,
                        ),
                ),
              ],
              if (reason != null)
                Row(
                  spacing: 8,
                  children: [
                    Dot(reasonColor!),
                    Flexible(
                      child: Text(
                        reason,
                        style: TextStyle(
                          color: reasonColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (g.kind != GroupKind.storyboard) ...[
                FoldToggle(
                  key: Key('fold-cuts-${g.key}'),
                  state: Folds.cutsInDetails,
                  label: '${g.total} cut',
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: Folds.cutsInDetails,
                  builder: (context, open, _) => !open
                      ? const SizedBox.shrink()
                      : Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final t in g.tasks)
                              _CutChip(
                                waiting:
                                    t.handedOff ||
                                    (t.waiting && t.status.isOpen),
                                task: t,
                                onTap: onTask == null ? null : () => onTask!(t),
                                onLongPress: onTaskLongPress == null
                                    ? null
                                    : () => onTaskLongPress!(t),
                                picked:
                                    t.id == highlighted ||
                                    (isPicked?.call(t) ?? false),
                              ),
                          ],
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One cut in the opened details: its status, name, take, length and own
/// deadline; faded when on hold or pulled.
class _CutChip extends StatelessWidget {
  const _CutChip({
    required this.task,
    required this.picked,
    this.waiting = false,
    this.onTap,
    this.onLongPress,
  });

  final TaskRow task;

  /// Filled: picked for an action, or the one the timer runs on.
  final bool picked;
  final VoidCallback? onTap;

  /// Long press: picks the cut.
  final VoidCallback? onLongPress;

  /// On hold or pulled: drawn faint.
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final t = task;
    final Widget face = DecoratedBox(
      decoration: BoxDecoration(
        color: picked ? c.selected : c.panel,
        border: Border.all(
          color: t.sharedLabel != null
              ? Theme.of(context).colorScheme.primary
              : c.line,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Dot(c.of(t.status)),
            if (t.handedOff)
              Icon(Icons.person_remove_outlined, size: 12, color: c.muted)
            else if (t.waiting && t.status.isOpen)
              const HoldMark(),
            Flexible(
              child: FitText.rich(
                tooltip: false,
                TextSpan(
                  children: [
                    TextSpan(
                      text: taskLabel(t),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: t.handedOff
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (t.sharedLabel != null)
                      TextSpan(
                        text: ' ${t.sharedLabel}',
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    if (t.take > 1)
                      TextSpan(
                        text: ' T${t.take}',
                        style: TextStyle(
                          color: c.retake,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    TextSpan(
                      text: '  ${formatLength(t.lengthMs)}',
                      style: TextStyle(color: c.muted),
                    ),
                    if (t.dueOverridden)
                      TextSpan(
                        text: '  ${formatDate(t.dueAt)}',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final child = waiting ? Opacity(opacity: 0.45, child: face) : face;
    if (onTap == null && onLongPress == null) return child;
    return InkWell(
      key: Key('cut-${task.id}'),
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

extension on PartDetails {
  /// 「보유 n · 대기 m」, the hold's reason and expected day, and the
  /// hold button.
  Widget _holdRow(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final waitingTask = g.tasks.where((t) => t.waiting && t.status.isOpen);
    final note = waitingTask.isEmpty ? null : waitingTask.first;
    final allWaiting = g.inHand == 0 && g.waiting > 0;
    return Row(
      spacing: 10,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: S.inHand.f({'n': g.inHand}),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (g.waiting > 0)
                  TextSpan(
                    text: '  ·  ${S.onHold.f({'n': g.waiting})}',
                    style: TextStyle(color: c.submitted),
                  ),
                if (note?.waitReason case final r?)
                  TextSpan(
                    text: '  $r',
                    style: TextStyle(color: c.muted),
                  ),
                if (note?.waitUntil case final u?)
                  TextSpan(
                    text: '  → ${formatDate(u)}',
                    style: TextStyle(color: c.muted),
                  ),
              ],
            ),
            key: Key('holding-${g.key}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (onHold != null && g.tasks.any((t) => t.status.isOpen))
          TextButton.icon(
            key: Key('hold-${g.key}'),
            onPressed: onHold,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(
              allWaiting
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
              size: 16,
            ),
            label: Text(allWaiting ? S.unhold.t : S.hold.t),
          ),
      ],
    );
  }
}

String _perDay(UsualPace p) {
  final d = p.perDay;
  return d == null ? '—' : '${d.toStringAsFixed(1)} cut';
}

/// Everything a unit's opened details need from the app — one bundle the
/// shell makes once and every view that opens a unit (list, timeline)
/// uses, so the details are the same widget wired the same way.
class UnitWiring {
  const UnitWiring({
    this.signals = const {},
    this.paces = const {},
    this.paceOf,
    this.selection,
    this.onTaskTap,
    this.onDue,
    this.onKickoff,
    this.onPlan,
    this.onHold,
    this.revisionsOf,
    this.onEditRevision,
  });

  /// Deadline and plan signals by group key (reader.signals).
  final Map<String, GroupSignals> signals;

  /// Usual speeds by stage name (reader.stagePaces).
  final Map<String, StagePace> paces;

  /// A unit's pace when [signals] has none.
  final Pace? Function(PartGroup group)? paceOf;

  /// Tasks picked for an action, shared by every view.
  final TaskSelection? selection;

  /// A cut tapped in the details (starts the timer, or picks it while
  /// picking); null: taps pick.
  final ValueChanged<TaskRow>? onTaskTap;

  final void Function(PartGroup group, DateTime due)? onDue;
  final void Function(PartGroup group, DateTime kickoff)? onKickoff;
  final void Function(PartGroup group, DateTime start, DateTime end)? onPlan;
  final void Function(PartGroup group)? onHold;
  final Future<List<DueRevision>> Function(PartGroup group)? revisionsOf;
  final void Function(PartGroup group, int revision, DateTime due)?
  onEditRevision;

  /// The details of [p], opened under its line or row.
  Widget details(PartGroup p) {
    final sel = selection;
    return PartDetails(
      group: p,
      pace: signals[p.key]?.pace ?? paceOf?.call(p),
      plan: signals[p.key]?.plan,
      usual: paces[p.stageName],
      isPicked: sel?.has,
      onTask: onTaskTap ?? sel?.toggleTask,
      onDue: onDue == null ? null : (d) => onDue!(p, d),
      onTaskLongPress: sel?.toggleTask,
      onKickoff: onKickoff == null ? null : (d) => onKickoff!(p, d),
      onPlanStart: onPlan == null
          ? null
          : (d) => onPlan!(p, d, p.planEndAt ?? p.dueAt ?? d),
      onPlanEnd: onPlan == null
          ? null
          : (d) => onPlan!(p, p.planStartAt ?? p.kickoffAt ?? d, d),
      onHold: onHold == null ? null : () => onHold!(p),
      loadRevisions: revisionsOf == null || p.kind == GroupKind.noPart
          ? null
          : () => revisionsOf!(p),
      onEditRevision: onEditRevision == null
          ? null
          : (n, d) => onEditRevision!(p, n, d),
    );
  }
}
