import 'package:flutter/foundation.dart';
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
import '../palette.dart';
import '../fit_text.dart';
import '../part_line.dart';

/// The user's own work periods laid out on parallel lanes (「라인 1 · 2」).
/// Bars past the lane count go to red 「넘침」 rows. A long press picks a
/// bar up to drop it on another lane (it stays pinned there); its ends
/// move the work's start and end. A tap opens the work in a panel beside
/// the board (under it in portrait).
class WorkView extends StatefulWidget {
  const WorkView({
    super.key,
    required this.lanes,
    required this.parts,
    required this.now,
    required this.layout,
    this.days = const ChartDays(),
    this.onPin,
    this.onClearPins,
    this.onPlan,
    this.laneNames = const [],
    this.onAddLane,
    this.onEditLane,
    this.wiring,
    this.onRulerPress,
    this.onRulerEvent,
  });

  /// What a tapped bar's opened work acts through (the shell's); null
  /// keeps bars closed.
  final UnitWiring? wiring;

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

  /// Rest weekdays, days off and holidays for the background.
  final ChartDays days;

  final void Function(String groupKey, int lane)? onPin;
  final VoidCallback? onClearPins;

  /// Saves a dragged work start and end (local days).
  final void Function(PartGroup group, DateTime start, DateTime end)? onPlan;

  /// The date ruler's long press (a new event of no episode: a day off,
  /// a note) and its events' taps.
  final ValueChanged<DateTime>? onRulerPress;
  final ValueChanged<EventRow>? onRulerEvent;

  @override
  State<WorkView> createState() => _WorkViewState();
}

class _WorkViewState extends State<WorkView> {
  /// The work whose bar was tapped open.
  String? _open;

  /// Opens [key]'s details (another bar's switch over).
  void _show(String key) => setState(() => _open = key);

  void _close() => setState(() => _open = null);

  PartGroup? get _openGroup => _open == null ? null : widget.parts[_open];

  /// The running view's days; only the board's date parts follow it.
  late final _window = RunningWindow(widget.now, widget.layout.size);

  @override
  void didUpdateWidget(WorkView old) {
    super.didUpdateWidget(old);
    _window.update(widget.now, widget.layout.size);
  }

  @override
  void dispose() {
    _window.dispose();
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
    final rowCount = lanes == null
        ? 0
        : (lanes.usedLanes > lanes.lanes ? lanes.usedLanes : lanes.lanes);
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
                  icon: Icons.auto_fix_high,
                  selected: false,
                  onTap: widget.onClearPins,
                ),
              ValueListenableBuilder<bool>(
                valueListenable: chartMonthView,
                builder: (context, month, _) => month
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<ChartWindow>(
                        valueListenable: _window,
                        builder: (context, w, _) => ChartPager(days: w.shown),
                      ),
              ),
              const MonthViewToggle(),
            ],
          ),
          Expanded(
            child: _withSide(
              context,
              ValueListenableBuilder<bool>(
                valueListenable: chartMonthView,
                builder: (context, month, _) => lanes == null
                    ? const SizedBox.shrink()
                    : month
                    ? MonthStack(
                        first: DateTime(widget.now.year, widget.now.month - 1),
                        last: _lastMonth(lanes),
                        month: (context, w) =>
                            _board(context, FixedWindow(w), lanes, [
                              for (var r = 0; r < rowCount; r++)
                                if (_laneIn(lanes, r, w)) r,
                            ], month: true),
                      )
                    : ValueListenableBuilder<ChartWindow>(
                        valueListenable: _window,
                        builder: (context, w, board) => ChartViewport(
                          days: w.shown,
                          labelWidth: _labelWidth,
                          child: board!,
                        ),
                        child: _board(context, _window, lanes, [
                          for (var r = 0; r < rowCount; r++) r,
                        ], month: false),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One board of the lanes [rows] over [window]: the running view's,
  /// or one month's in the month view.
  Widget _board(
    BuildContext context,
    ValueListenable<ChartWindow> window,
    LaneLayout lanes,
    List<int> rows, {
    required bool month,
  }) {
    final c = AppColors.of(context);
    final red = Theme.of(context).colorScheme.error;
    return ChartBoard(
      window: window,
      onDayLongPress: widget.onRulerPress,
      onDayEvent: widget.onRulerEvent,
      today: widget.now,
      days: widget.days,
      labelWidth: _labelWidth,
      rowCount: rows.length,
      shrinkWrap: month,
      corner: _corner(context),
      label: (context, i) => _laneLabel(context, lanes, rows[i]),
      bars: (context, i, window) => [
        for (final s in lanes.spans)
          if (lanes.laneOf[s.key] == rows[i])
            _bar(s, window, lanes.overflow, red),
      ],
      rowTint: (i) =>
          rows[i] >= lanes.lanes ? red.withValues(alpha: 0.06) : null,
      rowWrap: (i, child) => DragTarget<String>(
        key: Key('lane-${rows[i]}'),
        onAcceptWithDetails: (d) => widget.onPin?.call(d.data, rows[i]),
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
    );
  }

  /// Lane [r] has work in [w].
  static bool _laneIn(LaneLayout lanes, int r, ChartWindow w) =>
      lanes.spans.any(
        (s) =>
            lanes.laneOf[s.key] == r &&
            w.indexOf(s.end) >= 0 &&
            w.indexOf(s.start) < w.days,
      );

  /// The month view runs to the last work's month (at least two on).
  DateTime _lastMonth(LaneLayout lanes) {
    var last = DateTime(widget.now.year, widget.now.month + 2);
    for (final s in lanes.spans) {
      final d = s.end.toLocal();
      if (d.isAfter(last)) last = DateTime(d.year, d.month);
    }
    return last;
  }

  /// The opened work's head (its list line, a tap closes) and details.
  Widget _openPanel(BuildContext context, PartGroup g) {
    final w = widget.wiring!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartLine(
          group: g,
          now: widget.now,
          dayStartMinutes: 0,
          expanded: true,
          selected: false,
          signals: w.signals[g.key],
          onDue: w.onDue == null ? null : (d) => w.onDue!(g, d),
          onTap: _close,
        ),
        Flexible(
          child: SingleChildScrollView(child: w.details(g, client: true)),
        ),
      ],
    );
  }

  /// The board, with the opened work's panel beside it (landscape) or
  /// under it (portrait), so the chart stays in view.
  Widget _withSide(BuildContext context, Widget board) {
    final g = _openGroup;
    if (g == null || widget.wiring == null) {
      return board;
    }
    // A tap on the board off every bar (bars take their own taps first:
    // the deepest tap wins) closes the details.
    board = GestureDetector(
      key: const Key('work-blank'),
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: board,
    );
    final c = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final beside = box.maxWidth > box.maxHeight;
        final panel = DecoratedBox(
          key: const Key('work-open-panel'),
          decoration: BoxDecoration(
            color: c.panel,
            border: beside
                ? Border(left: BorderSide(color: c.line))
                : Border(top: BorderSide(color: c.line)),
          ),
          child: _openPanel(context, g),
        );
        return beside
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: board),
                  SizedBox(
                    width: (box.maxWidth * 0.42).clamp(280.0, 420.0),
                    child: panel,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: board),
                  SizedBox(height: box.maxHeight * 0.5, child: panel),
                ],
              );
      },
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
        child: FitText(
          over ? S.overflow.t : _laneName(r),
          tooltip: false,
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

  Widget _bar(Span s, ChartWindow window, Set<String> overflow, Color red) {
    final g = widget.parts[s.key];
    final label = g == null ? s.key : workBarLabel(g);
    final pinned = widget.lanes!.pinned.contains(s.key);
    // The stage's colour; work past the lanes is ringed red.
    final color = g == null ? stageTones.first : stageColor(g.stageName);
    // Past the lanes, or overlapping in its own lane: ringed red.
    final over =
        overflow.contains(s.key) || widget.lanes!.overlapping.contains(s.key);
    return ChartBar(
      key: Key('work-bar-${s.key}'),
      window: window,
      start: s.start,
      end: s.end,
      color: color,
      textColor: barInk,
      outline: over ? red : null,
      label: pinned ? '• $label' : label,
      onDates: g == null || widget.onPlan == null
          ? null
          : (a, b) => widget.onPlan!(g, a, b),
      wrapBody: (face) {
        final open = _open == s.key;
        final ring = open
            ? DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(color: barInk, width: 2),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: face,
              )
            : face;
        final body = LongPressDraggable<String>(
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
                  color: barInk,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: face),
          child: ring,
        );
        return body;
      },
      onTap: g == null || widget.wiring == null ? null : () => _show(s.key),
    );
  }
}

/// 「별빛 정류장 #07 · 원화 · 4 cut」.
String workBarLabel(PartGroup g) =>
    '${g.workTitle} ${g.episodeNumber} · ${stageText(g.stageName)} · '
    '${g.kind == GroupKind.storyboard ? groupCount(g) : '${g.total} cut'}';
