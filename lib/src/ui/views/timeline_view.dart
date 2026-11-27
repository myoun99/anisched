import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../due_button.dart';
import '../format.dart';
import '../selection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chart.dart';
import '../text/strings.dart';

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
    this.toolbar,
    this.onReorder,
    this.onDue,
  });

  /// Sets a unit's deadline (tap on its D label).
  final void Function(PartGroup group, DateTime due)? onDue;

  /// Turns on the rows' drag grips; gets the shown keys in their new order.
  final ValueChanged<List<String>>? onReorder;

  /// Controls before the pager (the shell's sort and filter buttons);
  /// null shows the row count.
  final List<Widget>? toolbar;

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
  void _onView() => setState(() {});

  @override
  void initState() {
    super.initState();
    chartView.addListener(_onView);
  }

  @override
  void dispose() {
    chartView.removeListener(_onView);
    super.dispose();
  }

  double get _labelWidth => switch (widget.layout.size) {
    SizeClass.wide => 250,
    SizeClass.medium => 210,
    SizeClass.narrow => 150,
  };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final window = ChartWindow.of(
      widget.now,
      widget.layout.size,
      chartView.value,
    );
    final rows = widget.parts;
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ViewToolbar(
            children: [
              ...?widget.toolbar,
              if (widget.toolbar == null)
                Text(
                  S.items.f({'n': rows.length}),
                  style: TextStyle(color: c.muted),
                ),
              ChartPager(
                onShift: (d) => chartView.value = chartView.value.scrolled(d),
                onToday: () =>
                    chartView.value = ChartView(days: chartView.value.days),
                onZoom: (zoomIn) => chartView.value = chartView.value.stepped(
                  window.days,
                  zoomIn: zoomIn,
                ),
              ),
            ],
          ),
          Expanded(
            child: ChartViewport(
              days: window.days,
              labelWidth: _labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                        child: ReorderableListView.builder(
                          scrollController: controller,
                          buildDefaultDragHandles: false,
                          itemCount: rows.length,
                          itemExtent: 46,
                          onReorderItem: (from, to) {
                            final keys = [for (final r in rows) r.key];
                            keys.insert(to, keys.removeAt(from));
                            widget.onReorder?.call(keys);
                          },
                          itemBuilder: (context, i) => _TimelineRow(
                            key: ValueKey(rows[i].key),
                            index: widget.onReorder == null ? null : i,
                            group: rows[i],
                            window: window,
                            now: widget.now,
                            labelWidth: _labelWidth,
                            narrow: widget.layout.size == SizeClass.narrow,
                            restWeekdays: widget.restWeekdays,
                            onSchedule: widget.onSchedule,
                            onDue: widget.onDue,
                            selection: widget.selection,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
    this.index,
    required this.group,
    required this.window,
    required this.now,
    required this.labelWidth,
    required this.narrow,
    required this.restWeekdays,
    this.onSchedule,
    this.selection,
    this.onDue,
  });

  final void Function(PartGroup group, DateTime due)? onDue;

  /// Row index for the drag grip; null hides it.
  final int? index;
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
      padding: EdgeInsets.only(left: index == null ? 10 : 0, right: 10),
      child: Row(
        spacing: 6,
        children: [
          if (index != null)
            ReorderableDragStartListener(
              index: index!,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: SizedBox(
                  key: Key('tl-grip-${g.key}'),
                  width: 20,
                  height: 46,
                  child: Icon(Icons.drag_indicator, size: 16, color: c.faint),
                ),
              ),
            ),
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
          DueButton(
            key: Key('tl-due-${g.key}'),
            due: g.dueAt,
            onPicked: onDue == null ? null : (d) => onDue!(g, d),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                due.text,
                style: TextStyle(
                  fontSize: 12,
                  color: due.tone == DueTone.late
                      ? Theme.of(context).colorScheme.error
                      : c.muted,
                  fontWeight: due.tone == DueTone.late ? FontWeight.w700 : null,
                ),
              ),
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
