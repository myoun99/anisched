import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/size_class.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text/strings.dart';

/// Local calendar day as a UTC midnight, so day differences are exact.
DateTime chartDay(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  return DateTime.utc(l.year, l.month, l.day);
}

/// The days a chart shows: [days] columns from [start].
@immutable
class ChartWindow {
  const ChartWindow(this.start, this.days);

  /// Today placed about a third in from the left, scrolled by [shift]
  /// days; [days] columns (zoom), or a count by size when null.
  factory ChartWindow.around(
    DateTime now,
    SizeClass size, {
    int shift = 0,
    int? days,
  }) {
    final n =
        days ??
        switch (size) {
          SizeClass.wide => 35,
          SizeClass.medium => 24,
          SizeClass.narrow => 10,
        };
    final before = (n * 0.3).round();
    final today = chartDay(now);
    return ChartWindow(today.add(Duration(days: shift - before)), n);
  }

  /// The window for the shared [view] at [size].
  factory ChartWindow.of(DateTime now, SizeClass size, ChartView view) =>
      ChartWindow.around(now, size, shift: view.shift, days: view.days);

  final DateTime start;
  final int days;

  /// Column of [t] (may fall outside 0..days-1).
  int indexOf(DateTime t) => chartDay(t).difference(start).inDays;

  DateTime dayAt(int i) => start.add(Duration(days: i));

  @override
  bool operator ==(Object other) =>
      other is ChartWindow && other.start == start && other.days == days;

  @override
  int get hashCode => Object.hash(start, days);
}

/// Where the date area is scrolled to and how far it is zoomed, shared by
/// the timeline and the work view and kept while the app runs.
@immutable
class ChartView {
  const ChartView({this.shift = 0, this.days});

  /// Days scrolled from the default position (negative = the past).
  final int shift;

  /// Days shown; null = the default for the screen size.
  final int? days;

  static const zoomSteps = [7, 10, 14, 21, 28, 35, 49, 70, 105];
  static const minDays = 7;
  static const maxDays = 105;

  ChartView scrolled(int by) => ChartView(shift: shift + by, days: days);

  ChartView zoomed(int toDays) =>
      ChartView(shift: shift, days: toDays.clamp(minDays, maxDays));

  /// One step in (fewer days) or out (more), from [current] days.
  ChartView stepped(int current, {required bool zoomIn}) {
    const steps = zoomSteps;
    final next = zoomIn
        ? steps.lastWhere((d) => d < current, orElse: () => steps.first)
        : steps.firstWhere((d) => d > current, orElse: () => steps.last);
    return zoomed(next);
  }
}

/// The shared scroll and zoom of the date area.
final chartView = ValueNotifier<ChartView>(const ChartView());

/// Lets the date area be dragged sideways (empty space only: bars keep
/// their own drags), scrolled with a wheel or trackpad, and zoomed with a
/// pinch or Ctrl + wheel. Updates [chartView]; the chart redraws only
/// the days in view.
class ChartViewport extends StatefulWidget {
  const ChartViewport({
    super.key,
    required this.days,
    required this.labelWidth,
    required this.child,
  });

  /// Days in view now (for the pixel-to-day scale).
  final int days;

  /// Width left of the dates (row labels), not part of the scale.
  final double labelWidth;
  final Widget child;

  @override
  State<ChartViewport> createState() => _ChartViewportState();
}

class _ChartViewportState extends State<ChartViewport> {
  double _width = 1;
  double _carry = 0;
  final _pointers = <int, Offset>{};
  double? _pinchStart;
  int _pinchDays = 0;

  double get _dayWidth => _width / widget.days;

  void _pan(double dx) {
    _carry += dx;
    final whole = (_carry / _dayWidth).truncate();
    if (whole == 0) return;
    _carry -= whole * _dayWidth;
    chartView.value = chartView.value.scrolled(-whole);
  }

  void _zoomTo(double factor) {
    final days = (_pinchDays / factor).round();
    if (days != widget.days) chartView.value = chartView.value.zoomed(days);
  }

  double _spread() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _width = (box.maxWidth - widget.labelWidth).clamp(1, double.infinity);
        return Listener(
          onPointerDown: (e) {
            _pointers[e.pointer] = e.position;
            if (_pointers.length == 2) {
              _pinchStart = _spread();
              _pinchDays = widget.days;
            }
          },
          onPointerMove: (e) {
            if (!_pointers.containsKey(e.pointer)) return;
            _pointers[e.pointer] = e.position;
            final start = _pinchStart;
            if (_pointers.length == 2 && start != null && start > 0) {
              _zoomTo(_spread() / start);
            }
          },
          onPointerUp: (e) {
            _pointers.remove(e.pointer);
            if (_pointers.length < 2) _pinchStart = null;
          },
          onPointerCancel: (e) {
            _pointers.remove(e.pointer);
            if (_pointers.length < 2) _pinchStart = null;
          },
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            final keys = HardwareKeyboard.instance;
            if (keys.isControlPressed || keys.isMetaPressed) {
              chartView.value = chartView.value.stepped(
                widget.days,
                zoomIn: e.scrollDelta.dy < 0,
              );
            } else if (e.scrollDelta.dx != 0 || keys.isShiftPressed) {
              final d = e.scrollDelta.dx != 0
                  ? e.scrollDelta.dx
                  : e.scrollDelta.dy;
              _pan(-d);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _carry = 0,
            onHorizontalDragUpdate: (d) {
              if (_pointers.length < 2) _pan(d.delta.dx);
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Toolbar paging and zoom buttons: 「◀ 오늘 ▶ − +」.
class ChartPager extends StatelessWidget {
  const ChartPager({
    super.key,
    required this.onShift,
    required this.onToday,
    this.onZoom,
  });

  final ValueChanged<int> onShift;
  final VoidCallback onToday;

  /// Zoom one step: true = in (fewer days).
  final ValueChanged<bool>? onZoom;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      _IconFace(
        key: const Key('chart-prev'),
        icon: Icons.chevron_left,
        onTap: () => onShift(-7),
      ),
      ToolbarButton(
        key: const Key('chart-today'),
        label: S.today.t,
        selected: false,
        onTap: onToday,
      ),
      _IconFace(
        key: const Key('chart-next'),
        icon: Icons.chevron_right,
        onTap: () => onShift(7),
      ),
      if (onZoom != null) ...[
        const SizedBox(width: 4),
        _IconFace(
          key: const Key('chart-zoom-out'),
          icon: Icons.remove,
          onTap: () => onZoom!(false),
        ),
        _IconFace(
          key: const Key('chart-zoom-in'),
          icon: Icons.add,
          onTap: () => onZoom!(true),
        ),
      ],
    ],
  );
}

class _IconFace extends StatelessWidget {
  const _IconFace({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

/// Paint counts per chart layer, for tests that pin which layer redraws.
@visibleForTesting
abstract final class ChartPaints {
  static int background = 0;
  static int today = 0;
  static int preview = 0;

  static void reset() => background = today = preview = 0;
}

/// The colour today's column is washed with, light or dark.
Color chartTodayWash(BuildContext context) {
  final red = Theme.of(context).colorScheme.error;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return red.withValues(alpha: dark ? 0.16 : 0.09);
}

/// The background layer: rest-day shading and, when days are wide enough,
/// faint day lines. Changes only with the window, rest days or theme.
class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.window,
    required this.rest,
    required this.shade,
    required this.line,
  });

  final ChartWindow window;
  final Set<int> rest;
  final Color shade;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.background++;
    final dw = size.width / window.days;
    final fill = Paint()..color = shade;
    for (var i = 0; i < window.days; i++) {
      if (rest.contains(window.dayAt(i).weekday)) {
        canvas.drawRect(Rect.fromLTWH(i * dw, 0, dw, size.height), fill);
      }
    }
    if (dw >= 14) {
      final p = Paint()
        ..color = line.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (var i = 1; i < window.days; i++) {
        canvas.drawLine(Offset(i * dw, 0), Offset(i * dw, size.height), p);
      }
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.window != window ||
      old.shade != shade ||
      old.line != line ||
      !setEquals(old.rest, rest);
}

/// The today layer: today's whole column, washed, on the same day grid
/// as the bars.
class _TodayPainter extends CustomPainter {
  _TodayPainter({
    required this.window,
    required this.today,
    required this.wash,
  });

  final ChartWindow window;
  final int today;
  final Color wash;

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.today++;
    if (today < 0 || today >= window.days) return;
    final dw = size.width / window.days;
    canvas.drawRect(
      Rect.fromLTWH(today * dw, 0, dw, size.height),
      Paint()..color = wash,
    );
  }

  @override
  bool shouldRepaint(_TodayPainter old) =>
      old.window != window || old.today != today || old.wash != wash;
}

/// Background and today layers for one strip of days (header or body),
/// each behind its own repaint boundary.
class _DayLayers extends StatelessWidget {
  const _DayLayers({
    required this.window,
    required this.today,
    required this.restWeekdays,
  });

  final ChartWindow window;
  final DateTime today;
  final Set<int> restWeekdays;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _BackgroundPainter(
              window: window,
              rest: restWeekdays,
              shade: c.panelAlt,
              line: c.line,
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: _TodayPainter(
              window: window,
              today: window.indexOf(today),
              wash: chartTodayWash(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Month labels over day numbers, drawn in one painter.
class ChartHeader extends StatelessWidget {
  const ChartHeader({
    super.key,
    required this.window,
    required this.today,
    required this.restWeekdays,
  });

  final ChartWindow window;
  final DateTime today;
  final Set<int> restWeekdays;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = DefaultTextStyle.of(context).style;
    return SizedBox(
      height: 44,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DayLayers(window: window, today: today, restWeekdays: restWeekdays),
          RepaintBoundary(
            child: CustomPaint(
              painter: _HeaderPainter(
                window: window,
                today: window.indexOf(today),
                rest: restWeekdays,
                ink: style.color ?? c.muted,
                muted: c.muted,
                faint: c.faint,
                red: Theme.of(context).colorScheme.error,
                style: style,
                lang: appLang.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPainter extends CustomPainter {
  _HeaderPainter({
    required this.window,
    required this.today,
    required this.rest,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.red,
    required this.style,
    required this.lang,
  });

  final ChartWindow window;
  final int today;
  final Set<int> rest;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color red;
  final TextStyle style;
  final Lang lang;

  TextPainter _text(String s, Color color, {bool bold = false}) => TextPainter(
    text: TextSpan(
      text: s,
      style: style.copyWith(
        fontSize: 11,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  /// Narrow days keep a number only on Mondays (and today), so the
  /// numbers never run together when zoomed out.
  bool _labelled(int i, double dw) {
    if (dw >= 16 || i == today) return true;
    if ((i - today).abs() < (dw >= 8 ? 2 : 4)) return false;
    final d = window.dayAt(i);
    return d.weekday == DateTime.monday &&
        (dw >= 8 ||
            (DateTime.utc(
                      d.year,
                      d.month,
                      d.day,
                    ).difference(DateTime.utc(2024)).inDays ~/
                    7)
                .isEven);
  }

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.background++;
    final dw = size.width / window.days;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < window.days; i++) {
      final d = window.dayAt(i);
      if (i == 0 || d.day == 1) {
        _text(
          monthName(d.month, lang),
          ink,
          bold: true,
        ).paint(canvas, Offset(i * dw + 4, 4));
      }
      if (!_labelled(i, dw)) continue;
      final t = _text(
        '${d.day}',
        i == today ? red : (rest.contains(d.weekday) ? faint : muted),
        bold: i == today,
      );
      final x = dw >= 16 ? i * dw + (dw - t.width) / 2 : i * dw + 1;
      t.paint(canvas, Offset(x, 24));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeaderPainter old) =>
      old.window != window ||
      old.today != today ||
      old.ink != ink ||
      old.muted != muted ||
      old.lang != lang ||
      !setEquals(old.rest, rest);
}

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
    required this.restWeekdays,
    required this.labelWidth,
    required this.rowCount,
    required this.label,
    required this.bars,
    this.rowKey,
    this.rowWrap,
    this.rowTint,
    this.onReorder,
  });

  final ChartWindow window;
  final DateTime today;
  final Set<int> restWeekdays;
  final double labelWidth;
  final int rowCount;

  /// The row's label column.
  final Widget Function(BuildContext context, int row) label;

  /// The row's bars ([ChartBar]s) over the date area.
  final List<Widget> Function(BuildContext context, int row) bars;

  /// Keeps a row's identity (needed with [onReorder]).
  final Key Function(int row)? rowKey;

  /// Wraps a whole row, e.g. as a drop target.
  final Widget Function(int row, Widget child)? rowWrap;

  /// A wash over a row's date area (e.g. overflow lanes).
  final Color? Function(int row)? rowTint;

  /// Rows can be reordered by their [ReorderableDragStartListener]s.
  final void Function(int from, int to)? onReorder;

  static const rowExtent = 46.0;
  static const barTop = 12.0;
  static const barHeight = 22.0;

  @override
  State<ChartBoard> createState() => _ChartBoardState();
}

class _ChartBoardState extends State<ChartBoard> {
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (tint != null) ColoredBox(color: tint),
                ...widget.bars(context, i),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.rowWrap case final wrap?) row = wrap(i, row);
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final reorder = widget.onReorder;
    return _DragScope(
      drag: _drag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                SizedBox(width: widget.labelWidth),
                Expanded(
                  child: ChartHeader(
                    window: widget.window,
                    today: widget.today,
                    restWeekdays: widget.restWeekdays,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: widget.labelWidth),
                  child: _DayLayers(
                    window: widget.window,
                    today: widget.today,
                    restWeekdays: widget.restWeekdays,
                  ),
                ),
                RepaintBoundary(
                  child: OwnScroll(
                    builder: (controller) => Scrollbar(
                      controller: controller,
                      child: reorder == null
                          ? ListView.builder(
                              controller: controller,
                              itemCount: widget.rowCount,
                              itemExtent: ChartBoard.rowExtent,
                              itemBuilder: _row,
                            )
                          : ReorderableListView.builder(
                              scrollController: controller,
                              buildDefaultDragHandles: false,
                              itemCount: widget.rowCount,
                              itemExtent: ChartBoard.rowExtent,
                              onReorderItem: reorder,
                              itemBuilder: _row,
                            ),
                    ),
                  ),
                ),
                Padding(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which end of a bar a drag moves.
enum BarEdge { start, end }

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
  });

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

  Widget _handle(BarEdge edge, double handle) => GestureDetector(
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
      child: SizedBox(width: handle),
    ),
  );

  Widget _face() {
    final face = SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: widget.label == null
              ? null
              : Text(
                  widget.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                  ),
                ),
        ),
      ),
    );
    return widget.wrapBody?.call(face) ?? face;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _dayWidth = box.maxWidth / widget.window.days;
        final dw = _dayWidth;
        final s = chartDay(widget.start);
        final e = chartDay(widget.end);
        final left = widget.window.indexOf(s) * dw;
        final width = (e.difference(s).inDays + 1) * dw;
        // Two grips never wider than a third of the bar each.
        final handle = (width / 3).clamp(2.0, 14.0);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: left,
              width: width,
              top: ChartBoard.barTop,
              height: ChartBoard.barHeight,
              child: Opacity(
                opacity: _edge != null ? 0.4 : (widget.faded ? 0.35 : 1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.onDates != null)
                        _handle(BarEdge.start, handle),
                      Expanded(child: _face()),
                      if (widget.onDates != null) _handle(BarEdge.end, handle),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
