import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../format.dart';
import '../selection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chart.dart';

/// The production schedule only: one bar per unit from kickoff to
/// deadline, the deadline's D-day on the right of the name. Dragging a
/// bar's end moves the kickoff or the deadline.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.parts,
    required this.now,
    required this.layout,
    this.restWeekdays = const {DateTime.saturday, DateTime.sunday},
    this.onSchedule,
    this.selection,
  });

  /// Units in display order.
  final List<PartGroup> parts;
  final DateTime now;
  final ScreenLayout layout;
  final Set<int> restWeekdays;

  /// Saves a dragged kickoff and deadline (local days); null keeps the
  /// bars fixed.
  final void Function(PartGroup group, DateTime kickoff, DateTime due)?
  onSchedule;

  final TaskSelection? selection;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  int _shift = 0;

  double get _labelWidth => switch (widget.layout.size) {
    SizeClass.wide => 250,
    SizeClass.medium => 210,
    SizeClass.narrow => 150,
  };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final window = ChartWindow.around(
      widget.now,
      widget.layout.size,
      shift: _shift,
    );
    final rows = widget.parts;
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ViewToolbar(
            children: [
              Text('${rows.length}건', style: TextStyle(color: c.muted)),
              ChartPager(
                onShift: (d) => setState(() => _shift += d),
                onToday: () => setState(() => _shift = 0),
              ),
            ],
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                SizedBox(width: _labelWidth),
                Expanded(
                  child: ChartHeader(
                    window: window,
                    today: widget.now,
                    restWeekdays: widget.restWeekdays,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: OwnScroll(
              builder: (controller) => Scrollbar(
                controller: controller,
                child: ListView.builder(
                  controller: controller,
                  itemCount: rows.length,
                  itemExtent: 46,
                  itemBuilder: (context, i) => _TimelineRow(
                    key: ValueKey(rows[i].key),
                    group: rows[i],
                    window: window,
                    now: widget.now,
                    labelWidth: _labelWidth,
                    narrow: widget.layout.size == SizeClass.narrow,
                    restWeekdays: widget.restWeekdays,
                    onSchedule: widget.onSchedule,
                    selection: widget.selection,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.group,
    required this.window,
    required this.now,
    required this.labelWidth,
    required this.narrow,
    required this.restWeekdays,
    this.onSchedule,
    this.selection,
  });

  final PartGroup group;
  final ChartWindow window;
  final DateTime now;
  final double labelWidth;
  final bool narrow;
  final Set<int> restWeekdays;
  final void Function(PartGroup group, DateTime kickoff, DateTime due)?
  onSchedule;
  final TaskSelection? selection;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final due = dueLabel(g.dueAt, now, g.status);
    final handed = !g.status.isOpen || g.status == TaskStatus.submitted;
    final start = g.kickoffAt;
    final end = g.dueAt;
    final sel = selection;
    Widget label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (!narrow)
                        TextSpan(
                          text: '${g.workTitle} ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      TextSpan(
                        text: g.episodeNumber,
                        style: TextStyle(
                          color: narrow ? null : c.muted,
                          fontWeight: narrow ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  '${g.stageName} · ${g.kind == GroupKind.noPart ? g.cutsLabel : groupTitle(g)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.muted),
                ),
              ],
            ),
          ),
          Text(
            due.text,
            style: TextStyle(
              fontSize: 12,
              color: due.tone == DueTone.late
                  ? Theme.of(context).colorScheme.error
                  : c.muted,
              fontWeight: due.tone == DueTone.late ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
    if (sel != null) {
      label = ListenableBuilder(
        listenable: sel,
        builder: (context, child) => Material(
          color: sel.of(g) != Picked.none ? c.selected : Colors.transparent,
          child: InkWell(
            onLongPress: () => sel.toggleGroup(g),
            onTap: sel.isEmpty ? null : () => sel.toggleGroup(g),
            child: child,
          ),
        ),
        child: label,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: labelWidth, child: label),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ChartGrid(
                  window: window,
                  today: now,
                  restWeekdays: restWeekdays,
                ),
                if (start != null && end != null && !end.isBefore(start))
                  ChartBar(
                    key: Key('tl-bar-${g.key}'),
                    window: window,
                    start: start,
                    end: end,
                    top: 15,
                    height: 16,
                    color: Color.lerp(
                      Theme.of(context).colorScheme.onSurface,
                      c.panel,
                      0.38,
                    )!,
                    faded: handed,
                    onDates: onSchedule == null
                        ? null
                        : (s, e) => onSchedule!(g, s, e),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
