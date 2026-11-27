import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/lanes.dart';
import '../../models/progress.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chart.dart';

/// The user's own work periods laid out on parallel lanes (「라인 1 · 2」).
/// Bars past the lane count go to red 「넘침」 rows. A long press picks a
/// bar up to drop it on another lane (it stays pinned there); its ends
/// move the work's start and end.
class WorkView extends StatefulWidget {
  const WorkView({
    super.key,
    required this.lanes,
    required this.parts,
    required this.now,
    required this.layout,
    this.restWeekdays = const {DateTime.saturday, DateTime.sunday},
    this.onPin,
    this.onClearPins,
    this.onPlan,
  });

  /// The data lane's layout (basis: work); null while loading.
  final LaneLayout? lanes;

  /// Units by group key, for the bars' labels.
  final Map<String, PartGroup> parts;
  final DateTime now;
  final ScreenLayout layout;
  final Set<int> restWeekdays;

  final void Function(String groupKey, int lane)? onPin;
  final VoidCallback? onClearPins;

  /// Saves a dragged work start and end (local days).
  final void Function(PartGroup group, DateTime start, DateTime end)? onPlan;

  @override
  State<WorkView> createState() => _WorkViewState();
}

class _WorkViewState extends State<WorkView> {
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
    SizeClass.wide => 100,
    SizeClass.medium => 90,
    SizeClass.narrow => 64,
  };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final lanes = widget.lanes;
    final window = ChartWindow.of(
      widget.now,
      widget.layout.size,
      chartView.value,
    );
    final rowCount = lanes == null
        ? 0
        : (lanes.usedLanes > lanes.lanes ? lanes.usedLanes : lanes.lanes);
    final today = chartDay(widget.now);
    final busy = lanes == null
        ? 0
        : lanes.spans
              .where((s) => !s.start.isAfter(today) && !s.end.isBefore(today))
              .length;
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ViewToolbar(
            children: [
              if (lanes != null && lanes.pinned.isNotEmpty)
                ToolbarButton(
                  key: const Key('lanes-auto'),
                  label: '자동 배치',
                  selected: false,
                  onTap: widget.onClearPins,
                ),
              if (lanes != null && widget.layout.size != SizeClass.narrow)
                SizedBox(
                  height: 34,
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      '오늘 $busy / ${lanes.lanes}',
                      style: TextStyle(color: c.muted),
                    ),
                  ),
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
                        child: ListView.builder(
                          controller: controller,
                          itemCount: rowCount,
                          itemExtent: 52,
                          itemBuilder: (context, r) =>
                              _laneRow(context, lanes!, r, window),
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

  Widget _laneRow(
    BuildContext context,
    LaneLayout lanes,
    int r,
    ChartWindow window,
  ) {
    final c = AppColors.of(context);
    final red = Theme.of(context).colorScheme.error;
    final accent = Theme.of(context).colorScheme.primary;
    final over = r >= lanes.lanes;
    final overflow = lanes.overflow;
    final spans = [
      for (final s in lanes.spans)
        if (lanes.laneOf[s.key] == r) s,
    ];
    return DragTarget<String>(
      key: Key('lane-$r'),
      onAcceptWithDetails: (d) => widget.onPin?.call(d.data, r),
      builder: (context, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? c.selected
              : over
              ? red.withValues(alpha: 0.06)
              : null,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _labelWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  over ? '넘침' : '라인 ${r + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: over ? red : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ChartGrid(
                    window: window,
                    today: widget.now,
                    restWeekdays: widget.restWeekdays,
                  ),
                  for (final s in spans) _bar(s, window, overflow, accent, red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(
    Span s,
    ChartWindow window,
    Set<String> overflow,
    Color accent,
    Color red,
  ) {
    final g = widget.parts[s.key];
    final label = g == null ? s.key : workBarLabel(g);
    final pinned = widget.lanes!.pinned.contains(s.key);
    final color = overflow.contains(s.key) ? red : accent;
    return ChartBar(
      key: Key('work-bar-${s.key}'),
      window: window,
      start: s.start,
      end: s.end,
      top: 13,
      height: 26,
      color: color,
      textColor: Colors.white,
      label: pinned ? '• $label' : label,
      onDates: g == null || widget.onPlan == null
          ? null
          : (a, b) => widget.onPlan!(g, a, b),
      wrapBody: (face) => LongPressDraggable<String>(
        data: s.key,
        feedback: Material(
          color: color,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: face),
        child: face,
      ),
    );
  }
}

/// 「별빛 정류장 #07 · 원화 · 4 cut」.
String workBarLabel(PartGroup g) =>
    '${g.workTitle} ${g.episodeNumber} · ${g.stageName} · '
    '${g.kind == GroupKind.storyboard ? groupCount(g) : '${g.total} cut'}';
