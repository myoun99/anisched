// A bar: its face, grips, cut ends; things placed on a day of a row.
part of 'chart.dart';

/// Which end of a bar a drag moves.
enum BarEdge { start, end }

/// A bar's end grip: a small button of another colour with 〈 or 〉, the
/// whole of it the place to drag. Only bars whose dates can be dragged
/// have them ([ChartBar.onDates]).
class BarGrip extends StatelessWidget {
  const BarGrip({
    super.key,
    required this.edge,
    required this.ink,
    this.width = maxWidth,
  });

  final BarEdge edge;

  /// The bar's ink: the grip's border and arrow.
  final Color ink;

  /// The grip's width, which is also its drag area.
  final double width;

  /// The widest a grip gets; on narrow days, half a day ([widthFor]).
  static const maxWidth = 16.0;

  /// The least room a label needs between two grips; less hides it.
  static const minLabel = 8.0;

  /// A grip's width for days [dayWidth] wide: at most half a day, so a
  /// one-day bar is just its two grips however far out the zoom goes.
  static double widthFor(double dayWidth) =>
      dayWidth / 2 < maxWidth ? dayWidth / 2 : maxWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          // Bars are light in both themes: a near-white face reads on them.
          decoration: BoxDecoration(
            color: const Color(0xF2FFFFFF),
            border: Border.all(color: ink.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
            child: Icon(
              edge == BarEdge.start ? Icons.chevron_left : Icons.chevron_right,
              size: 12,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// A date bar inside a [ChartBoard] row: [start]..[end] (days, both
/// included), on the same day cells as the background. Its two ends can
/// be dragged; while dragging, only the board's preview layer redraws,
/// and the new dates are reported once on release through [onDates].
class ChartBar extends StatefulWidget {
  const ChartBar({
    super.key,
    required this.window,
    required this.start,
    required this.end,
    required this.color,
    this.label,
    this.textColor,
    this.onDates,
    this.faded = false,
    this.wrapBody,
    this.outline,
  });

  /// A border round the bar (e.g. red for work past the lanes).
  final Color? outline;

  final ChartWindow window;
  final DateTime start;
  final DateTime end;
  final Color color;
  final String? label;
  final Color? textColor;
  final bool faded;

  /// Wraps the bar's face (between its edge handles), e.g. to make it a
  /// drag source.
  final Widget Function(Widget face)? wrapBody;

  /// New (start, end) after an edge drag; null makes the ends fixed.
  final void Function(DateTime start, DateTime end)? onDates;

  @override
  State<ChartBar> createState() => _ChartBarState();
}

class _ChartBarState extends State<ChartBar> {
  BarEdge? _edge;
  double _dx = 0;
  double _from = 0;
  double _dayWidth = 1;

  (DateTime, DateTime) _dates() {
    final s = chartDay(widget.start);
    final e = chartDay(widget.end);
    if (_edge == null) return (s, e);
    final d = Duration(days: (_dx / _dayWidth).round());
    return switch (_edge!) {
      BarEdge.start => (s.add(d).isAfter(e) ? e : s.add(d), e),
      BarEdge.end => (s, e.add(d).isBefore(s) ? s : e.add(d)),
    };
  }

  /// Publishes where the bar would land to the board's preview layer.
  void _preview() {
    final scope = context.getInheritedWidgetOfExactType<_DragScope>();
    final box = context.findRenderObject() as RenderBox?;
    if (scope == null || box == null) return;
    final (s, e) = _dates();
    final left = widget.window.indexOf(s) * _dayWidth;
    final width = (e.difference(s).inDays + 1) * _dayWidth;
    final origin = box.localToGlobal(Offset.zero);
    scope.drag.value = ChartDrag(
      Rect.fromLTWH(
        origin.dx + left,
        origin.dy + ChartBoard.barTop,
        width,
        ChartBoard.barHeight,
      ),
      widget.color,
    );
  }

  void _endPreview() {
    context.getInheritedWidgetOfExactType<_DragScope>()?.drag.value = null;
  }

  Color _ink(BuildContext context) =>
      widget.textColor ?? Theme.of(context).colorScheme.onSurface;

  Widget _handle(BarEdge edge, double width) => GestureDetector(
    key: Key('bar-${edge.name}'),
    behavior: HitTestBehavior.opaque,
    // Measured from where the finger went down, so nothing is lost while
    // the date area's own drag competes for the gesture.
    dragStartBehavior: DragStartBehavior.down,
    onHorizontalDragStart: (d) {
      setState(() => _edge = edge);
      _from = d.globalPosition.dx;
      _dx = 0;
      _preview();
    },
    onHorizontalDragUpdate: (d) {
      // No rebuild: only the preview layer redraws.
      _dx = d.globalPosition.dx - _from;
      _preview();
    },
    onHorizontalDragEnd: (_) {
      final (s, e) = _dates();
      _endPreview();
      setState(() => _edge = null);
      widget.onDates?.call(s, e);
    },
    onHorizontalDragCancel: () {
      _endPreview();
      setState(() => _edge = null);
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: BarGrip(edge: edge, width: width, ink: _ink(context)),
    ),
  );

  Widget _face({required bool label}) {
    // The label uses all the room it is given, no padding; tight bars
    // condense it (FitText). A bar that is a drag source keeps its long
    // press, so no tooltip there.
    final face = SizedBox.expand(
      child: Align(
        alignment: Alignment.centerLeft,
        child: widget.label == null || !label
            ? null
            : FitText(
                widget.label!,
                tooltip: widget.wrapBody == null,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.textColor,
                ),
              ),
      ),
    );
    return widget.wrapBody?.call(face) ?? face;
  }

  @override
  Widget build(BuildContext context) {
    ChartPaints.barBuilds++;
    return LayoutBuilder(
      builder: (context, box) {
        _dayWidth = box.maxWidth / widget.window.days;
        final dw = _dayWidth;
        final s = chartDay(widget.start);
        final e = chartDay(widget.end);
        final left = widget.window.indexOf(s) * dw;
        final width = (e.difference(s).inDays + 1) * dw;
        // The part inside the window; an end past it is cut (the bar
        // goes on in the next window or month).
        final from = left < 0 ? 0.0 : left;
        final to = left + width > box.maxWidth ? box.maxWidth : left + width;
        if (to <= from) return const SizedBox.shrink();
        final cutStart = left < -0.5;
        final cutEnd = left + width > box.maxWidth + 0.5;
        final grips = widget.onDates != null;
        final grip = BarGrip.widthFor(dw);
        final startEnd = cutStart
            ? CutMark(edge: BarEdge.start, width: grip, ink: _ink(context))
            : grips
            ? _handle(BarEdge.start, grip)
            : null;
        final endEnd = cutEnd
            ? CutMark(edge: BarEdge.end, width: grip, ink: _ink(context))
            : grips
            ? _handle(BarEdge.end, grip)
            : null;
        // The label takes every pixel between the ends, or hides.
        final room =
            to -
            from -
            (startEnd == null ? 0 : grip) -
            (endEnd == null ? 0 : grip);
        final showLabel = room >= BarGrip.minLabel;
        const r = Radius.circular(4);
        final bar = Opacity(
          opacity: _edge != null ? 0.4 : (widget.faded ? 0.35 : 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              // A cut end is square: the bar goes on past it.
              borderRadius: BorderRadius.horizontal(
                left: cutStart ? Radius.zero : r,
                right: cutEnd ? Radius.zero : r,
              ),
              // A faint edge keeps near-white bars (LO) visible.
              border: widget.outline == null
                  ? Border.all(color: barInk.withValues(alpha: 0.18))
                  : Border.all(color: widget.outline!, width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?startEnd,
                Expanded(child: _face(label: showLabel)),
                ?endEnd,
              ],
            ),
          ),
        );
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: from,
              width: to - from,
              top: ChartBoard.barTop,
              height: ChartBoard.barHeight,
              child: bar,
            ),
          ],
        );
      },
    );
  }
}

/// Where a bar is cut by its window's edge (it goes on in the next
/// window or month): a faint ⋯ in place of that end's grip.
class CutMark extends StatelessWidget {
  const CutMark({
    super.key,
    required this.edge,
    required this.width,
    required this.ink,
  });

  final BarEdge edge;
  final double width;
  final Color ink;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: Key('bar-cut-${edge.name}'),
    width: width,
    child: Center(
      child: Icon(
        Icons.more_horiz,
        size: 12,
        color: ink.withValues(alpha: 0.55),
      ),
    ),
  );
}

/// A row's empty date area answering a long press with the day under the
/// finger (a new event there). Goes first among a row's bars, so bars and
/// marks stay on top.
class ChartDayPress extends StatelessWidget {
  const ChartDayPress({
    super.key,
    required this.window,
    required this.onLongPress,
  });

  final ChartWindow window;
  final ValueChanged<DateTime> onLongPress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (d) {
        final i = (d.localPosition.dx / (box.maxWidth / window.days)).floor();
        onLongPress(window.dayAt(i.clamp(0, window.days - 1)));
      },
    ),
  );
}

/// Something placed in one day's cell of a row, at bar height (an
/// event's mark); nothing when the day is out of the window.
class ChartDayBox extends StatelessWidget {
  const ChartDayBox({
    super.key,
    required this.window,
    required this.day,
    required this.child,
    this.minWidth = 0,
  });

  final ChartWindow window;
  final DateTime day;
  final Widget child;

  /// At least this wide, running on over the next days (a title to read).
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final i = window.indexOf(day);
    if (i < 0 || i >= window.days) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final dw = box.maxWidth / window.days;
        final left = i * dw;
        final width = (dw > minWidth ? dw : minWidth).clamp(
          0.0,
          box.maxWidth - left,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              width: width,
              top: ChartBoard.barTop,
              height: ChartBoard.barHeight,
              child: child,
            ),
          ],
        );
      },
    );
  }
}
