import 'package:flutter/material.dart';

import '../models/catalogue.dart';
import '../models/progress.dart';
import 'format.dart';
import 'theme.dart';
import 'fit_text.dart';

extension StatusColor on AppColors {
  Color of(TaskStatus s) => switch (s) {
    TaskStatus.received => received,
    TaskStatus.inProgress => working,
    TaskStatus.submitted => submitted,
    TaskStatus.retake => retake,
  };

  /// A status as the colour of words (a cut's number): its own colour,
  /// but 받음's grey taken darker in light mode and lighter in dark so it
  /// reads as words.
  Color ink(TaskStatus s) => s == TaskStatus.received
      ? Color.lerp(
          muted,
          panel.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          0.3,
        )!
      : of(s);
}

/// Small filled dot, e.g. a status or a work colour.
class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Status word on a tint of its colour.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context).of(status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          status.label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
        ),
      ),
    );
  }
}

/// 「T2」 badge for a task on its second or later take; empty otherwise.
class TakeBadge extends StatelessWidget {
  const TakeBadge(this.take, {super.key});

  final int take;

  @override
  Widget build(BuildContext context) {
    if (take <= 1) return const SizedBox.shrink();
    final c = AppColors.of(context).retake;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          'T$take',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
        ),
      ),
    );
  }
}

/// Bar split by task status: submitted, done, in progress, retake, received.
class PartProgress extends StatelessWidget {
  const PartProgress(this.group, {super.key, this.width, this.height = 6});

  final PartGroup group;
  final double? width;
  final double height;

  static const _order = [
    TaskStatus.submitted,
    TaskStatus.inProgress,
    TaskStatus.retake,
    TaskStatus.received,
  ];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final counts = group.counts;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: ColoredBox(
          color: c.line,
          child: Row(
            spacing: 1,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in _order)
                if ((counts[s] ?? 0) > 0)
                  Expanded(
                    flex: counts[s]!,
                    child: ColoredBox(color: c.of(s)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The deadline label: quiet, red only once the deadline has passed.
class DueText extends StatelessWidget {
  const DueText(
    this.dueAt,
    this.status,
    this.now, {
    super.key,
    this.dayStartMinutes = 0,
  }) : days = null;

  /// From days already counted (e.g. a today entry's `dueInDays`).
  const DueText.days(this.days, this.status, {super.key})
    : dueAt = null,
      now = null,
      dayStartMinutes = 0;

  final DateTime? dueAt;
  final DateTime? now;
  final int? days;
  final TaskStatus status;
  final int dayStartMinutes;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = now == null
        ? dueLabelFromDays(days, status)
        : dueLabel(dueAt, now!, status, dayStartMinutes: dayStartMinutes);
    final late = l.tone == DueTone.late;
    return Text(
      l.text,
      style: TextStyle(
        color: late ? c.retake : c.muted,
        fontWeight: late ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A tappable segment in a segmented filter. Selection shows as fill only.
class SegmentButton extends StatelessWidget {
  const SegmentButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
    this.count,
    this.icon,
    this.tooltip,
    this.compact = false,
  });

  /// Narrow side padding, for rows of many short segments.
  final bool compact;

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final int? count;

  /// Drawn before the label; with an empty label, the button is the icon.
  final IconData? icon;

  /// Shown on hover or long press (icon-only buttons).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final button = Material(
      color: selected ? c.selected : c.panel,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              if (dot != null) Dot(dot!),
              if (icon != null)
                Icon(icon, size: 17, color: selected ? null : c.muted),
              if (label.isNotEmpty)
                Flexible(child: FitText(label, textAlign: TextAlign.center)),
              if (count != null)
                Text('$count', style: TextStyle(color: c.muted)),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Bordered row of [SegmentButton]s.
class SegmentGroup extends StatelessWidget {
  const SegmentGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, color: c.line),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The D slot: the deadline label, with the plan dot before it when the
/// plan asks for action.
class SignalLabel extends StatelessWidget {
  const SignalLabel({super.key, required this.due, required this.plan});

  final DueSignal due;
  final PlanSignal plan;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = dueSignalLabel(due);
    final dot = switch (planTone(plan)) {
      PlanTone.red => c.retake,
      PlanTone.amber => c.submitted,
      PlanTone.none => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (dot != null) Dot(dot, key: const Key('plan-dot')),
        Text(
          l.text,
          style: TextStyle(
            color: l.late ? c.retake : (l.quiet ? c.faint : c.muted),
            fontWeight: l.late ? FontWeight.w700 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// A toolbar button or drop-down face; picked state shows as fill.
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.dropdown = false,
    this.icon,
  });

  /// The words; with an [icon], only its tooltip (toolbars speak in
  /// icons — the user's rule).
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Shown instead of the label.
  final IconData? icon;

  /// Shows a drop-down arrow after the label.
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? c.selected : c.panel,
        border: Border.all(color: selected ? c.selected : c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 12 : 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final i?)
                Icon(i, size: 20, color: selected ? null : c.muted)
              else
                Text(label),
              if (dropdown && icon == null)
                Icon(Icons.arrow_drop_down, size: 20, color: c.muted),
            ],
          ),
        ),
      ),
    );
    final tapped = onTap == null
        ? body
        : InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: body,
          );
    return icon == null ? tapped : Tooltip(message: label, child: tapped);
  }
}

/// The row of controls above a view's list, at its right end (tools sit
/// on the right, 유저 2026-11-28).
class ViewToolbar extends StatelessWidget {
  const ViewToolbar({super.key, required this.children, this.basis});

  final List<Widget> children;

  /// On the left: what the view is drawn by (a small muted label).
  final ToolbarBasis? basis;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              // The label never takes the tools' room.
              if (basis case final b?) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.3),
                  child: b,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Wrap(
                  key: const Key('view-toolbar'),
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a chart view is drawn by, on its toolbar's left: an icon and a
/// few muted words (the timeline: the production schedule; the work tab:
/// my own work plan).
class ToolbarBasis extends StatelessWidget {
  const ToolbarBasis(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      key: const Key('toolbar-basis'),
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        Icon(icon, size: 15, color: c.muted),
        Flexible(
          child: FitText(text, style: TextStyle(fontSize: 12, color: c.muted)),
        ),
      ],
    );
  }
}

/// Gives a scroll view its own controller, so its always-visible
/// scrollbar never falls back to a shared one.
class OwnScroll extends StatefulWidget {
  const OwnScroll({super.key, required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<OwnScroll> createState() => _OwnScrollState();
}

class _OwnScrollState extends State<OwnScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

/// A cut's block: the one face of a cut on a card's details and on the
/// register's list — the plain edge (or [edge]), filled when [picked],
/// its [children] in a row (the number, then what goes with it).
class CutBlock extends StatelessWidget {
  const CutBlock({
    super.key,
    required this.children,
    this.picked = false,
    this.edge,
  });

  final List<Widget> children;
  final bool picked;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: picked ? c.selected : c.panel,
        border: Border.all(color: edge ?? c.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: children,
        ),
      ),
    );
  }
}

/// A card on the page: the second panel tone, a hairline and round
/// corners — the settings groups and the statistics tiles and charts.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A menu item's icon and words: every pop-up menu of the app (the file
/// menu, the picked-task bar's ⋯) draws its lines with this.
class MenuLine extends StatelessWidget {
  const MenuLine({
    super.key,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  /// Icon and words in this colour (a dangerous action's), when enabled.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = enabled ? color : c.faint;
    return Row(
      spacing: 10,
      children: [
        Icon(icon, size: 18, color: ink ?? c.muted),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: ink == null ? null : TextStyle(color: ink),
          ),
        ),
      ],
    );
  }
}

/// A dialog's title: its icon, then its words, from the left like every
/// name (the buttons sit on the right).
class DialogTitle extends StatelessWidget {
  const DialogTitle(this.icon, this.text, {super.key, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      Icon(icon, color: color),
      Flexible(child: Text(text)),
    ],
  );
}
