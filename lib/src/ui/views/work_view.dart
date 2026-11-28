import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/lanes.dart';
import '../../models/progress.dart';
import '../format.dart';
import '../theme.dart';
import '../instant.dart';
import '../widgets.dart';
import '../text/strings.dart';
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
    this.laneNames = const [],
    this.onAddLane,
    this.onEditLane,
  });

  /// The user's lane names (null = the number).
  final List<String?> laneNames;

  /// Adds a lane at the bottom (the header's +).
  final VoidCallback? onAddLane;

  /// A lane's edit window answered: a new name (blank = number), or
  /// removal.
  final void Function(int lane, {String? name, bool remove})? onEditLane;

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
    final red = Theme.of(context).colorScheme.error;
    final accent = Theme.of(context).colorScheme.primary;
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
                  label: S.autoPlace.t,
                  selected: false,
                  onTap: widget.onClearPins,
                ),
              if (lanes != null && widget.layout.size != SizeClass.narrow)
                SizedBox(
                  height: 34,
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      S.todayBusy.f({'a': busy, 'b': lanes.lanes}),
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                ),
              ChartPager(days: window.days),
            ],
          ),
          Expanded(
            child: ChartViewport(
              days: window.days,
              labelWidth: _labelWidth,
              child: ChartBoard(
                window: window,
                today: widget.now,
                restWeekdays: widget.restWeekdays,
                labelWidth: _labelWidth,
                rowCount: rowCount,
                corner: _corner(context),
                label: (context, r) => _laneLabel(context, lanes!, r),
                bars: (context, r) => [
                  for (final s in lanes!.spans)
                    if (lanes.laneOf[s.key] == r)
                      _bar(s, window, lanes.overflow, accent, red),
                ],
                rowTint: (r) =>
                    r >= lanes!.lanes ? red.withValues(alpha: 0.06) : null,
                rowWrap: (r, child) => DragTarget<String>(
                  key: Key('lane-$r'),
                  onAcceptWithDetails: (d) => widget.onPin?.call(d.data, r),
                  builder: (context, candidates, _) => candidates.isEmpty
                      ? child
                      : DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            color: c.selected.withValues(alpha: 0.5),
                          ),
                          child: child,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「라인」 over the lane labels, with + to add one.
  Widget _corner(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.laneHead.t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
          if (widget.onAddLane != null)
            IconButton(
              key: const Key('lane-add'),
              tooltip: S.addLane.t,
              onPressed: widget.onAddLane,
              icon: const Icon(Icons.add, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  String _laneName(int r) =>
      widget.laneNames.elementAtOrNull(r) ?? S.laneN.f({'n': r + 1});

  Widget _laneLabel(BuildContext context, LaneLayout lanes, int r) {
    final over = r >= lanes.lanes;
    final red = Theme.of(context).colorScheme.error;
    final label = Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 4),
        child: Text(
          over ? S.overflow.t : _laneName(r),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: over ? red : null,
          ),
        ),
      ),
    );
    final edit = widget.onEditLane;
    if (over || edit == null) return label;
    // A long press opens the lane's edit window.
    return InkWell(
      key: Key('lane-label-$r'),
      onLongPress: () => _editLane(context, r, lanes.lanes, edit),
      child: label,
    );
  }

  Future<void> _editLane(
    BuildContext context,
    int r,
    int count,
    void Function(int lane, {String? name, bool remove}) edit,
  ) async {
    final name = TextEditingController(
      text: widget.laneNames.elementAtOrNull(r) ?? '',
    );
    final answer = await showInstantDialog<({String? name, bool remove})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.laneN.f({'n': r + 1})),
        content: TextField(
          key: const Key('lane-name'),
          controller: name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.name.t,
            hintText: S.laneN.f({'n': r + 1}),
          ),
          onSubmitted: (v) =>
              Navigator.of(context).pop((name: v, remove: false)),
        ),
        actions: [
          TextButton.icon(
            key: const Key('lane-delete'),
            onPressed: count <= 1
                ? null
                : () => Navigator.of(context).pop((name: null, remove: true)),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(S.deleteLane.t),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.cancel.t),
          ),
          FilledButton(
            key: const Key('lane-ok'),
            onPressed: () =>
                Navigator.of(context).pop((name: name.text, remove: false)),
            child: Text(S.ok.t),
          ),
        ],
      ),
    );
    name.dispose();
    if (answer == null) return;
    edit(r, name: answer.name, remove: answer.remove);
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
    '${g.workTitle} ${episodeLabel(g.episodeNumber)} · ${g.stageName} · '
    '${g.kind == GroupKind.storyboard ? groupCount(g) : '${g.total} cut'}';
