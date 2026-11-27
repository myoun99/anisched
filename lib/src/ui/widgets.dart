import 'package:flutter/material.dart';

import '../controllers/overview.dart';
import '../models/catalogue.dart';
import 'theme.dart';

extension StatusColor on AppColors {
  Color of(TaskStatus s) => switch (s) {
    TaskStatus.received => received,
    TaskStatus.inProgress => working,
    TaskStatus.submitted => submitted,
    TaskStatus.retake => retake,
    TaskStatus.done => done,
  };
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

/// Bar split by task status: done, submitted, in progress, retake, received.
class PartProgress extends StatelessWidget {
  const PartProgress(this.part, {super.key, this.width, this.height = 6});

  final PartStage part;
  final double? width;
  final double height;

  static const _order = [
    TaskStatus.done,
    TaskStatus.submitted,
    TaskStatus.inProgress,
    TaskStatus.retake,
    TaskStatus.received,
  ];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
                if (part.count(s) > 0)
                  Expanded(
                    flex: part.count(s),
                    child: ColoredBox(color: c.of(s)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// D-day text coloured by urgency.
class DueText extends StatelessWidget {
  const DueText(this.dueAt, this.status, this.today, {super.key});

  final DateTime? dueAt;
  final TaskStatus status;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = dueLabel(dueAt, today, status);
    final (color, bold) = switch (l.tone) {
      DueTone.late => (c.retake, true),
      DueTone.soon => (c.submitted, true),
      DueTone.quiet || DueTone.none => (c.muted, false),
    };
    return Text(
      l.text,
      style: TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

const _wd = ['월', '화', '수', '목', '금', '토', '일'];

/// 「11/28(토)」.
String formatDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.month}/${l.day}(${_wd[l.weekday - 1]})';
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: selected ? c.selected : c.panel,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (dot != null) Dot(dot!),
              Text(label),
              if (count != null)
                Text('$count', style: TextStyle(color: c.muted)),
            ],
          ),
        ),
      ),
    );
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
