/// Shared pieces for views that list part × stage groups: a header, a
/// one-line summary and the details that open under it.
library;

import 'package:flutter/material.dart';

import '../models/progress.dart';
import 'format.dart';
import 'selection.dart';
import 'theme.dart';
import 'widgets.dart';

const caretW = 32.0;
const _progressW = 96.0;
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
            Expanded(child: Text('파트', style: style)),
            SizedBox(
              width: _progressW,
              child: Text('진행', style: style),
            ),
            SizedBox(
              width: _signalW,
              child: Text('마감', style: style, textAlign: TextAlign.right),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

/// Name, progress and the date signal for one group. Tapping opens it.
class PartLine extends StatelessWidget {
  const PartLine({
    super.key,
    required this.group,
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
  });

  final PartGroup group;
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
    final fill = switch (picked) {
      Picked.all => c.selected,
      Picked.some => Color.lerp(c.panel, c.selected, 0.5)!,
      Picked.none => selected ? c.hover : c.panel,
    };
    final line = Material(
      color: fill,
      child: InkWell(
        key: Key('line-${g.key}'),
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
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: groupTitle(g),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: '  ${g.stageName}',
                                style: TextStyle(color: c.muted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${g.workTitle} ${g.episodeNumber}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _progressW,
                    child: Row(
                      spacing: 6,
                      children: [
                        SizedBox(width: 44, child: PartProgress(g, height: 4)),
                        Text(
                          '${g.handed}/${g.total}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _signalW,
                    child: Align(
                      alignment: Alignment.centerRight,
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
        (signals?.plan is PlanNotStarted &&
            planTone(signals!.plan) == PlanTone.none);
    return fade ? Opacity(opacity: 0.5, child: line) : line;
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
  });

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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final accent = Theme.of(context).colorScheme.primary;
    final slack = g.slackDays;
    final perDay = pace?.perDay;
    final planText = g.planStartAt == null
        ? '—'
        : '${formatDate(g.planStartAt)} – '
              '${g.planEndAt == null ? '마감' : formatDate(g.planEndAt)}';
    final facts = <(String, String)>[
      ('마감', formatDate(g.dueAt)),
      ('내 계획', planText),
      ('여유', slack == null ? '—' : '$slack일'),
      ('하루', perDay == null ? '—' : '${perDay.toStringAsFixed(1)}컷'),
      ('단가', formatMoney(g.currency, g.pay)),
      ('시간', formatWorked(g.worked)),
      if (usual != null)
        ('평소', '${_perDay(usual!.overall)} · 최근 ${_perDay(usual!.recent)}'),
      if (plan case PlanNotStarted(:final startAt)) ('시작', formatDate(startAt)),
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
              Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  for (final (k, v) in facts)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Text(k, style: TextStyle(fontSize: 12, color: c.muted)),
                        Text(v),
                      ],
                    ),
                ],
              ),
              if (reason != null)
                Row(
                  spacing: 8,
                  children: [
                    Dot(reasonColor!),
                    Text(
                      reason,
                      style: TextStyle(
                        color: reasonColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              if (g.kind != GroupKind.storyboard)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final t in g.tasks)
                      _CutChip(
                        task: t,
                        highlighted: t.id == highlighted,
                        onTap: onTask == null ? null : () => onTask!(t),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                t.id == highlighted ||
                                    (isPicked?.call(t) ?? false)
                                ? c.selected
                                : c.panel,
                            border: Border.all(color: c.line),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                Dot(c.of(t.status)),
                                Text(
                                  taskLabel(t),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TakeBadge(t.take),
                                Text(
                                  formatLength(t.lengthMs),
                                  style: TextStyle(color: c.muted),
                                ),
                                if (t.dueOverridden)
                                  Text(
                                    formatDate(t.dueAt),
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CutChip extends StatelessWidget {
  const _CutChip({
    required this.task,
    required this.highlighted,
    required this.child,
    this.onTap,
  });

  final TaskRow task;
  final bool highlighted;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return InkWell(
      key: Key('cut-${task.id}'),
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: child,
    );
  }
}

String _perDay(UsualPace p) {
  final d = p.perDay;
  return d == null ? '—' : '${d.toStringAsFixed(1)}컷';
}
