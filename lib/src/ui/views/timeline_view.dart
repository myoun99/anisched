import 'package:flutter/foundation.dart';
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
import '../event_editor.dart';
import '../palette.dart';
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
    this.days = const ChartDays(),
    this.onSchedule,
    this.selection,
    this.toolbar,
    this.onReorder,
    this.onDue,
    this.details,
    this.events = const {},
    this.onNewEvent,
    this.onEvent,
    this.onRulerPress,
    this.onRulerEvent,
  });

  /// Dated events by episode (null: on no episode), shown on that
  /// episode's rows.
  final Map<int?, List<EventRow>> events;

  /// A long press on a row's day: a new event there.
  final void Function(PartGroup group, DateTime day)? onNewEvent;

  /// An event tapped: edit or remove it.
  final ValueChanged<EventRow>? onEvent;

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

  /// Rest weekdays, days off and holidays for the background.
  final ChartDays days;

  /// Saves a dragged kickoff and deadline (local days); null keeps the
  /// bars fixed.
  final void Function(PartGroup group, DateTime kickoff, DateTime due)?
  onSchedule;

  final TaskSelection? selection;

  /// The date ruler's long press (a new event of no episode: a day off,
  /// a note) and its events' taps.
  final ValueChanged<DateTime>? onRulerPress;
  final ValueChanged<EventRow>? onRulerEvent;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  /// The unit opened under its row, if any.
  String? _open;

  void _toggle(PartGroup g) =>
      setState(() => _open = _open == g.key ? null : g.key);

  /// The running view's days; only the board's date parts follow it.
  late final _window = RunningWindow(widget.now, widget.layout.size);

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    _window.update(widget.now, widget.layout.size);
  }

  @override
  void dispose() {
    _window.dispose();
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
    final rows = widget.parts;
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ViewToolbar(
            children: [
              ...?widget.toolbar,
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
            child: ValueListenableBuilder<bool>(
              valueListenable: chartMonthView,
              builder: (context, month, _) => month
                  ? MonthStack(
                      first: _firstMonth,
                      last: _lastMonth,
                      month: (context, w) => _board(context, FixedWindow(w), [
                        for (final g in rows)
                          if (_inWindow(g, w)) g,
                      ], month: true),
                    )
                  : ValueListenableBuilder<ChartWindow>(
                      valueListenable: _window,
                      // The viewport only needs the day count (a zoom).
                      builder: (context, w, board) => ChartViewport(
                        days: w.shown,
                        labelWidth: _labelWidth,
                        child: board!,
                      ),
                      child: _board(context, _window, rows, month: false),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// One board of [rows] over [window]: the running view's, or one
  /// month's in the month view (shrink-wrapped, not reordered).
  Widget _board(
    BuildContext context,
    ValueListenable<ChartWindow> window,
    List<PartGroup> rows, {
    required bool month,
  }) => ChartBoard(
    window: window,
    onDayLongPress: widget.onRulerPress,
    onDayEvent: widget.onRulerEvent ?? widget.onEvent,
    shrinkWrap: month,
    today: widget.now,
    days: widget.days,
    labelWidth: _labelWidth,
    rowCount: rows.length,
    rowKey: (i) => ValueKey(rows[i].key),
    onReorder: month || widget.onReorder == null
        ? null
        : (from, to) {
            final keys = [for (final r in rows) r.key];
            keys.insert(to, keys.removeAt(from));
            widget.onReorder!(keys);
          },
    label: (context, i) => _TimelineLabel(
      index: month || widget.onReorder == null ? null : i,
      group: rows[i],
      now: widget.now,
      narrow: widget.layout.size == SizeClass.narrow,
      onDue: widget.onDue,
      selection: widget.selection,
      open: _open == rows[i].key,
      onOpen: widget.details == null ? null : () => _toggle(rows[i]),
    ),
    bars: (context, i, window) => _bars(context, rows[i], window),
    below: widget.details == null
        ? null
        : (context, i) =>
              _open == rows[i].key ? widget.details!(rows[i]) : null,
  );

  /// The unit's bar falls in [w] (the month view's rows).
  static bool _inWindow(PartGroup g, ChartWindow w) {
    final s = g.kickoffAt;
    final e = g.dueAt;
    if (s == null || e == null) return false;
    return w.indexOf(e) >= 0 && w.indexOf(s) < w.days;
  }

  /// The month view runs from last month to the last deadline's month
  /// (at least two months on).
  DateTime get _firstMonth => DateTime(widget.now.year, widget.now.month - 1);

  DateTime get _lastMonth {
    var last = DateTime(widget.now.year, widget.now.month + 2);
    for (final g in widget.parts) {
      final d = g.dueAt?.toLocal();
      if (d != null && d.isAfter(last)) last = DateTime(d.year, d.month);
    }
    return last;
  }

  List<Widget> _bars(BuildContext context, PartGroup g, ChartWindow window) {
    final start = g.kickoffAt;
    final end = g.dueAt;
    final dated = start != null && end != null && !end.isBefore(start);
    final handed = !g.status.isOpen; // submitted or done
    final onSchedule = widget.onSchedule;
    final onNew = widget.onNewEvent;
    bool onBar(DateTime d) =>
        dated &&
        !chartDay(d).isBefore(chartDay(start)) &&
        !chartDay(d).isAfter(chartDay(end));
    return [
      // A long press on the row's days puts an event there.
      if (onNew != null)
        ChartDayPress(window: window, onLongPress: (d) => onNew(g, d)),
      if (dated)
        ChartBar(
          key: Key('tl-bar-${g.key}'),
          window: window,
          start: start,
          end: end,
          color: stageColor(g.stageName),
          textColor: barInk,
          faded: handed || (g.waiting > 0 && g.inHand == 0),
          onDates: onSchedule == null ? null : (s, e) => onSchedule(g, s, e),
          // A tap on the bar opens the row (as the work tab's bars do).
          onTap: widget.details == null
              ? null
              : () => setState(() => _open = g.key),
        ),
      for (final e in widget.events[g.episodeId] ?? const <EventRow>[])
        ChartDayBox(
          key: Key('tl-event-${g.key}-${e.id}'),
          window: window,
          day: e.date,
          minWidth: 72,
          child: EventMark(
            event: e,
            onBar: onBar(e.date),
            onTap: widget.onEvent == null ? null : () => widget.onEvent!(e),
          ),
        ),
    ];
  }
}

/// An event in its day cell: a small flag and its title, inside the bar
/// when it falls on it (ink on the bar), else a chip of its own.
class EventMark extends StatelessWidget {
  const EventMark({
    super.key,
    required this.event,
    required this.onBar,
    this.onTap,
  });

  final EventRow event;
  final bool onBar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = onBar ? barInk : Theme.of(context).colorScheme.onSurface;
    final time = event.timeMinutes;
    return Tooltip(
      message: [
        if (time != null) eventTimeLabel(time),
        event.title,
        if (event.note != null) event.note!,
      ].join('  '),
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: onBar
              ? const BoxDecoration()
              : BoxDecoration(
                  color: c.panelAlt,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(4),
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 1,
              children: [
                Icon(Icons.flag, size: 10, color: ink),
                Flexible(
                  child: FitText(
                    event.title,
                    tooltip: false,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                      TextSpan(
                        text: '${g.workTitle} ${g.episodeNumber} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: stageText(g.stageName),
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                if (partCutsLine(g).isNotEmpty)
                  FitText(
                    partCutsLine(g),
                    tooltip: false,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
              ],
            ),
          ),
          // Two lines: days left (to the production deadline) over cuts
          // left. At most 72 wide; long words (6 j de retard) shrink.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 72),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DueButton(
                    key: Key('tl-due-${g.key}'),
                    title: S.pickDue.t,
                    due: g.dueAt,
                    onPicked: onDue == null ? null : (d) => onDue!(g, d),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
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
                                  : null,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          RoundBadge(g.dueRevision),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      cutsLeftLabel(g),
                      key: Key('tl-left-${g.key}'),
                      style: TextStyle(fontSize: 11, color: c.muted),
                    ),
                  ),
                ],
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
