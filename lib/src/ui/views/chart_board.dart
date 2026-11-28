// The board: header, background, rows of bars and the drag preview, each its
// own layer.
part of 'chart.dart';

/// The bar being dragged: where it would land, painted on its own layer.
class ChartDrag {
  const ChartDrag(this.rect, this.color);

  /// In global coordinates.
  final Rect rect;
  final Color color;
}

/// Hands the board's drag-preview notifier to its bars.
class _DragScope extends InheritedWidget {
  const _DragScope({required this.drag, required super.child});

  final ValueNotifier<ChartDrag?> drag;

  @override
  bool updateShouldNotify(_DragScope old) => old.drag != drag;
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.drag, this.box, this.ink) : super(repaint: drag);

  final ValueNotifier<ChartDrag?> drag;
  final RenderBox? Function() box;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.preview++;
    final d = drag.value;
    final b = box();
    if (d == null || b == null || !b.attached) return;
    final r = d.rect.shift(-b.localToGlobal(Offset.zero));
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = d.color.withValues(alpha: 0.55));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.ink != ink;
}

/// The chart both date tabs use: a header, then rows of a label column
/// and a date area, in layers — background (rest days, day lines), today's
/// column, the rows with their bars, and the drag preview — each behind
/// its own repaint boundary, so dragging redraws the preview only and
/// scrolling the dates leaves the bars' data alone.
class ChartBoard extends StatefulWidget {
  const ChartBoard({
    super.key,
    required this.window,
    required this.today,
    this.days = const ChartDays(),
    required this.labelWidth,
    required this.rowCount,
    required this.label,
    required this.bars,
    this.rowKey,
    this.rowWrap,
    this.rowTint,
    this.onReorder,
    this.corner,
    this.below,
    this.shrinkWrap = false,
    this.onDayLongPress,
    this.onDayEvent,
    this.ruler,
  });

  /// Which ruler rows show (a chart tab's [rulerRows]); null: the
  /// defaults.
  final ValueListenable<RulerRows>? ruler;

  /// What opens under a row, the full width of the board (label column
  /// and dates); null when the row is closed.
  final Widget? Function(BuildContext context, int row)? below;

  /// The days shown: a running window that scrolls and zooms
  /// ([RunningWindow]), or a month's ([FixedWindow]). Only the parts that
  /// depend on it listen — the header, the background and each row's bar
  /// area — so moving the days leaves the row labels alone.
  final ValueListenable<ChartWindow> window;
  final DateTime today;

  /// Rest weekdays, days off and holidays, marked on the background.
  final ChartDays days;

  /// The ruler's long press (a new event of no episode) and its events'
  /// taps; see [ChartHeader].
  final ValueChanged<DateTime>? onDayLongPress;
  final ValueChanged<EventRow>? onDayEvent;

  /// As tall as its rows, not scrolling them itself: one of several
  /// boards stacked in an outer list (the month view's months).
  final bool shrinkWrap;
  final double labelWidth;
  final int rowCount;

  /// The header's left cell, over the row labels (e.g. 「라인 +」).
  final Widget? corner;

  /// The row's label column.
  final Widget Function(BuildContext context, int row) label;

  /// The row's bars ([ChartBar]s) over the date area.
  final List<Widget> Function(BuildContext context, int row, ChartWindow window)
  bars;

  /// Keeps a row's identity (needed with [onReorder]).
  final Key Function(int row)? rowKey;

  /// Wraps a whole row, e.g. as a drop target.
  final Widget Function(int row, Widget child)? rowWrap;

  /// A wash over a row's date area (e.g. overflow lanes).
  final Color? Function(int row)? rowTint;

  /// Rows can be reordered by their [ReorderableDragStartListener]s.
  final void Function(int from, int to)? onReorder;

  static const rowExtent = 46.0;
  // A bar fills its row but for a hair above and below, where the row's
  // background (stripes, days off) just shows.
  static const barTop = 2.0;
  static const barHeight = 42.0;

  @override
  State<ChartBoard> createState() => _ChartBoardState();
}

final _defaultRows = ValueNotifier<RulerRows>((
  year: false,
  month: true,
  weekday: true,
));

class _ChartBoardState extends State<ChartBoard> {
  /// A running window's part day ([RunningWindow.slide]): the date areas
  /// slide by it, painted only. None for a month's fixed window.
  ValueListenable<double>? get _slide => switch (widget.window) {
    final RunningWindow w => w.slide,
    _ => null,
  };

  final _drag = ValueNotifier<ChartDrag?>(null);
  final _previewKey = GlobalKey();

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  Widget _row(BuildContext context, int i) {
    final c = AppColors.of(context);
    final tint = widget.rowTint?.call(i);
    Widget row = DecoratedBox(
      key: widget.rowKey?.call(i),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: widget.labelWidth,
            child: ColoredBox(color: c.panel, child: widget.label(context, i)),
          ),
          Expanded(
            child: ValueListenableBuilder<ChartWindow>(
              valueListenable: widget.window,
              builder: (context, window, _) => DaySlide(
                window: window,
                slide: _slide,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (tint != null) ColoredBox(color: tint),
                    ...widget.bars(context, i, window),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.below != null || widget.shrinkWrap) {
      // No fixed extent then: each row keeps its own height.
      row = SizedBox(height: ChartBoard.rowExtent, child: row);
    }
    if (widget.below != null) {
      if (widget.below!(context, i) case final open?) {
        row = Column(
          key: widget.rowKey?.call(i),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [row, open],
        );
      } else if (widget.rowKey != null) {
        row = KeyedSubtree(key: widget.rowKey!(i), child: row);
      }
    }
    if (widget.rowWrap case final wrap?) row = wrap(i, row);
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final reorder = widget.onReorder;
    final layers = Padding(
      padding: EdgeInsets.only(left: widget.labelWidth),
      child: ValueListenableBuilder<ChartWindow>(
        valueListenable: widget.window,
        builder: (context, window, _) => DaySlide(
          window: window,
          slide: _slide,
          child: _DayLayers(
            window: window,
            today: widget.today,
            days: widget.days,
          ),
        ),
      ),
    );
    final rows = RepaintBoundary(
      child: OwnScroll(
        builder: (controller) => Scrollbar(
          controller: controller,
          child: reorder == null
              ? ListView.builder(
                  controller: controller,
                  itemCount: widget.rowCount,
                  // Rows can open (below): heights vary then.
                  itemExtent: widget.below == null
                      ? ChartBoard.rowExtent
                      : null,
                  itemBuilder: _row,
                )
              : ReorderableListView.builder(
                  scrollController: controller,
                  buildDefaultDragHandles: false,
                  itemCount: widget.rowCount,
                  itemExtent: widget.below == null
                      ? ChartBoard.rowExtent
                      : null,
                  onReorderItem: reorder,
                  itemBuilder: _row,
                ),
        ),
      ),
    );
    final preview = Padding(
      padding: EdgeInsets.only(left: widget.labelWidth),
      child: IgnorePointer(
        child: ClipRect(
          child: RepaintBoundary(
            child: CustomPaint(
              key: _previewKey,
              painter: _PreviewPainter(
                _drag,
                () =>
                    _previewKey.currentContext?.findRenderObject()
                        as RenderBox?,
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
    return _SlideScope(
      slide: _slide,
      child: _DragScope(
        drag: _drag,
        child: Column(
          mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  SizedBox(width: widget.labelWidth, child: widget.corner),
                  Expanded(
                    child: ValueListenableBuilder<ChartWindow>(
                      valueListenable: widget.window,
                      builder: (context, window, _) => DaySlide(
                        window: window,
                        slide: _slide,
                        child: ValueListenableBuilder<RulerRows>(
                          valueListenable: widget.ruler ?? _defaultRows,
                          builder: (context, rows, _) => ChartHeader(
                            window: window,
                            today: widget.today,
                            days: widget.days,
                            rows: rows,
                            onDayLongPress: widget.onDayLongPress,
                            onEvent: widget.onDayEvent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.shrinkWrap)
              Stack(
                children: [
                  Positioned.fill(child: layers),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.rowCount; i++)
                        _row(context, i),
                    ],
                  ),
                  Positioned.fill(child: preview),
                ],
              )
            else
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [layers, rows, preview],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
