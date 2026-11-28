import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/progress.dart';
import '../due_button.dart';
import '../hold.dart';
import '../format.dart';
import '../selection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chart.dart';
import '../text/strings.dart';
import '../fit_text.dart';

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
    this.details,
  });

  /// A unit's details (the list's own, from the shell's wiring), opened
  /// under its row across the whole board by a tap on the row's label.
  final Widget Function(PartGroup group)? details;

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

  /// The unit opened under its row, if any.
  String? _open;

  void _toggle(PartGroup g) =>
      setState(() => _open = _open == g.key ? null : g.key);

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
                rowCount: rows.length,
                rowKey: (i) => ValueKey(rows[i].key),
                onReorder: widget.onReorder == null
                    ? null
                    : (from, to) {
                        final keys = [for (final r in rows) r.key];
                        keys.insert(to, keys.removeAt(from));
                        widget.onReorder!(keys);
                      },
                label: (context, i) => _TimelineLabel(
                  index: widget.onReorder == null ? null : i,
                  group: rows[i],
                  now: widget.now,
                  narrow: widget.layout.size == SizeClass.narrow,
                  onDue: widget.onDue,
                  selection: widget.selection,
                  open: _open == rows[i].key,
                  onOpen: widget.details == null
                      ? null
                      : () => _toggle(rows[i]),
                ),
                bars: (context, i) => _bars(context, rows[i], window),
                below: widget.details == null
                    ? null
                    : (context, i) => _open == rows[i].key
                          ? widget.details!(rows[i])
                          : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _bars(BuildContext context, PartGroup g, ChartWindow window) {
    final c = AppColors.of(context);
    final start = g.kickoffAt;
    final end = g.dueAt;
    if (start == null || end == null || end.isBefore(start)) return const [];
    final handed = !g.status.isOpen; // submitted or done
    final onSchedule = widget.onSchedule;
    return [
      ChartBar(
        key: Key('tl-bar-${g.key}'),
        window: window,
        start: start,
        end: end,
        color: Color.lerp(
          Theme.of(context).colorScheme.onSurface,
          c.panel,
          0.38,
        )!,
        faded: handed || (g.waiting > 0 && g.inHand == 0),
        onDates: onSchedule == null ? null : (s, e) => onSchedule(g, s, e),
      ),
    ];
  }
}

class _TimelineLabel extends StatelessWidget {
  const _TimelineLabel({
    this.index,
    required this.group,
    required this.now,
    required this.narrow,
    this.selection,
    this.onDue,
    this.open = false,
    this.onOpen,
  });

  final void Function(PartGroup group, DateTime due)? onDue;

  /// Its details are open below.
  final bool open;

  /// Opens or closes the details (a tap, when nothing is being picked).
  final VoidCallback? onOpen;

  /// Row index for the drag grip; null hides it.
  final int? index;
  final PartGroup group;
  final DateTime now;
  final bool narrow;
  final TaskSelection? selection;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final due = dueLabel(g.dueAt, now, g.status);
    final sel = selection;
    final Widget label = Padding(
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
                FitText.rich(
                  tooltip: false,
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
                  style: const TextStyle(fontSize: 13),
                ),
                FitText(
                  '${stageText(g.stageName)} · ${groupTitle(g)}',
                  tooltip: false,
                  style: TextStyle(fontSize: 11, color: c.muted),
                ),
              ],
            ),
          ),
          // At most half the label; long words (6 j de retard) shrink.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 72),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: DueButton(
                key: Key('tl-due-${g.key}'),
                title: S.pickDue.t,
                due: g.dueAt,
                onPicked: onDue == null ? null : (d) => onDue!(g, d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        due.text,
                        style: TextStyle(
                          fontSize: 12,
                          color: due.tone == DueTone.late
                              ? Theme.of(context).colorScheme.error
                              : c.muted,
                          fontWeight: due.tone == DueTone.late
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                      RoundBadge(g.dueRevision),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final opened = open;
    return ListenableBuilder(
      listenable: sel ?? const _Quiet(),
      builder: (context, child) => Material(
        color: sel != null && sel.of(g) != Picked.none
            ? c.selected
            : (opened ? c.hover : Colors.transparent),
        child: InkWell(
          key: Key('tl-label-${g.key}'),
          onLongPress: sel == null ? null : () => sel.toggleGroup(g),
          // A tap picks while picking; otherwise it opens the details.
          onTap: sel != null && !sel.isEmpty
              ? () => sel.toggleGroup(g)
              : onOpen,
          child: child,
        ),
      ),
      child: label,
    );
  }
}

/// A listenable that never fires (no selection).
class _Quiet implements Listenable {
  const _Quiet();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
