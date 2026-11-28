import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/size_class.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text/strings.dart';
import '../fit_text.dart';
import '../palette.dart';

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

  /// Space held (desktop): a drag anywhere pans, bars included.
  bool _space = false;

  bool _onKey(KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.space) return false;
    final down = e is! KeyUpEvent;
    if (down != _space && mounted) setState(() => _space = down);
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

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
            if (_space && e.buttons & kPrimaryButton != 0) {
              _pan(e.delta.dx);
              return;
            }
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
              if (_pointers.length < 2 && !_space) _pan(d.delta.dx);
            },
            child: MouseRegion(
              cursor: _space ? SystemMouseCursors.grab : MouseCursor.defer,
              child: IgnorePointer(ignoring: _space, child: widget.child),
            ),
          ),
        );
      },
    );
  }
}

/// Toolbar paging and zoom buttons: 「◀ 오늘 ▶ − +」.
class ChartPager extends StatelessWidget {
  const ChartPager({super.key, required this.days});

  /// Days in view now.
  final int days;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      ToolbarButton(
        key: const Key('chart-today'),
        label: S.today.t,
        selected: false,
        onTap: () => chartView.value = ChartView(days: chartView.value.days),
      ),
      ZoomDrag(days: days),
    ],
  );
}

/// The zoom as one control (Anicel's timeline zoom): the days in view,
/// dragged sideways — right to zoom in (fewer days), left to zoom out —
/// one step of [ChartView.zoomSteps] per [stepPixels]; a wheel notch over
/// it is one step too. ↩️A − and a + stood here, with ◀ ▶ paging beside.
class ZoomDrag extends StatefulWidget {
  const ZoomDrag({super.key, required this.days});

  final int days;

  static const stepPixels = 14.0;

  @override
  State<ZoomDrag> createState() => _ZoomDragState();
}

class _ZoomDragState extends State<ZoomDrag> {
  double _carry = 0;

  void _step(bool zoomIn) => chartView.value = chartView.value.stepped(
    chartView.value.days ?? widget.days,
    zoomIn: zoomIn,
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Tooltip(
      message: S.zoomDrag.t,
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
            _step(e.scrollDelta.dy < 0);
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: const Key('chart-zoom'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => _carry = 0,
            onHorizontalDragUpdate: (d) {
              _carry += d.delta.dx;
              while (_carry.abs() >= ZoomDrag.stepPixels) {
                _step(_carry > 0);
                _carry -= _carry.sign * ZoomDrag.stepPixels;
              }
            },
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: c.panel,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Icon(Icons.zoom_in, size: 18, color: c.muted),
                  Text(
                    S.days.f({'n': widget.days}),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Icon(Icons.unfold_more, size: 16, color: c.faint),
                ],
              ),
            ),
          ),
        ),
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
  static int barBuilds = 0;

  static void reset() => background = today = preview = barBuilds = 0;
}

/// Which day columns carry a number and how the stripes run: every
/// [step] days, the step the smallest that leaves a number its real width.
/// Anchored to the calendar, not the window, so scrolling never moves which
/// days are numbered. Steps under a week count days; a week or more starts
/// on Mondays.
@immutable
class DayLabels {
  DayLabels(this.window, this.dayWidth, double numberWidth)
    : need = numberWidth + 6,
      step = _steps.firstWhere(
        (k) => dayWidth * k >= numberWidth + 6,
        orElse: () => _steps.last,
      );

  static const _steps = [1, 2, 3, 7, 14, 28];

  final ChartWindow window;
  final double dayWidth;

  /// Pixels a number needs, with a little room.
  final double need;
  final int step;

  static int _epochDay(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Weeks counted from a Monday (1970-01-01 was a Thursday).
  static int _week(int epochDay) => (epochDay + 3) ~/ 7;

  int _block(DateTime d) {
    final e = _epochDay(d);
    return step < 7 ? e ~/ step : _week(e) ~/ (step ~/ 7);
  }

  /// The first day of its stripe carries the number.
  bool labelled(int i) =>
      _block(window.dayAt(i - 1)) != _block(window.dayAt(i));

  /// Alternate stripes, Excel-like: one per numbered stretch.
  bool shaded(int i) => _block(window.dayAt(i)).isOdd;

  @override
  bool operator ==(Object other) =>
      other is DayLabels &&
      other.window == window &&
      other.dayWidth == dayWidth &&
      other.need == need;

  @override
  int get hashCode => Object.hash(window, dayWidth, need);
}

/// How wide a day number is drawn: the widest two digits at the header's
/// size.
double chartNumberWidth(BuildContext context) {
  final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 11);
  return (TextPainter(
    text: TextSpan(text: '30', style: style),
    textDirection: TextDirection.ltr,
  )..layout()).width;
}

/// The bands' grey: light enough that bars and the today wash read over
/// it, dark enough to count days by.
Color chartStripe(BuildContext context) {
  final c = AppColors.of(context);
  return Color.lerp(c.panel, c.line, 0.32)!;
}

/// Rest days: a step darker than a band, so both show.
Color chartRestShade(BuildContext context) {
  final c = AppColors.of(context);
  return c.line.withValues(alpha: 0.45);
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
    required this.stripe,
    required this.shade,
    required this.numberWidth,
  });

  final ChartWindow window;
  final Set<int> rest;

  /// Every other numbered stretch (Excel-like bands).
  final Color stripe;

  /// Rest days, over the bands.
  final Color shade;
  final double numberWidth;

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.background++;
    final dw = size.width / window.days;
    final labels = DayLabels(window, dw, numberWidth);
    final band = Paint()..color = stripe;
    final off = Paint()..color = shade;
    for (var i = 0; i < window.days; i++) {
      final r = Rect.fromLTWH(i * dw, 0, dw, size.height);
      if (labels.shaded(i)) canvas.drawRect(r, band);
      if (rest.contains(window.dayAt(i).weekday)) canvas.drawRect(r, off);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.window != window ||
      old.stripe != stripe ||
      old.shade != shade ||
      old.numberWidth != numberWidth ||
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
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _BackgroundPainter(
              window: window,
              rest: restWeekdays,
              stripe: chartStripe(context),
              shade: chartRestShade(context),
              numberWidth: chartNumberWidth(context),
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
                numberWidth: chartNumberWidth(context),
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
    required this.numberWidth,
  });

  final double numberWidth;
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

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.background++;
    final dw = size.width / window.days;
    final labels = DayLabels(window, dw, numberWidth);
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
      // A number where its stretch starts (and today's, always); none so
      // near today that the two would touch.
      final near = i != today && (i - today).abs() * dw < labels.need;
      if (i != today && (!labels.labelled(i) || near)) continue;
      final t = _text(
        '${d.day}',
        i == today ? red : (rest.contains(d.weekday) ? faint : muted),
        bold: i == today,
      );
      final x = labels.step == 1 ? i * dw + (dw - t.width) / 2 : i * dw + 2;
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
      old.numberWidth != numberWidth ||
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
    this.corner,
    this.below,
  });

  /// What opens under a row, the full width of the board (label column
  /// and dates); null when the row is closed.
  final Widget? Function(BuildContext context, int row)? below;

  final ChartWindow window;
  final DateTime today;
  final Set<int> restWeekdays;
  final double labelWidth;
  final int rowCount;

  /// The header's left cell, over the row labels (e.g. 「라인 +」).
  final Widget? corner;

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
    if (widget.below != null) {
      // No fixed extent then: each row keeps its own height.
      row = SizedBox(height: ChartBoard.rowExtent, child: row);
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
                SizedBox(width: widget.labelWidth, child: widget.corner),
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
      child: BarGrip(
        edge: edge,
        width: width,
        ink: widget.textColor ?? Theme.of(context).colorScheme.onSurface,
      ),
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
        final grips = widget.onDates != null;
        final grip = BarGrip.widthFor(dw);
        // The label gets the room between the grips, or none at all.
        final room = grips ? width - 2 * grip : width;
        final showLabel = room >= BarGrip.minLabel;
        final bar = Opacity(
          opacity: _edge != null ? 0.4 : (widget.faded ? 0.35 : 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
              // A faint edge keeps near-white bars (LO) visible.
              border: widget.outline == null
                  ? Border.all(color: barInk.withValues(alpha: 0.18))
                  : Border.all(color: widget.outline!, width: 1.5),
            ),
            // The label takes every pixel between the grips.
            child: grips
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _handle(BarEdge.start, grip),
                      Expanded(child: _face(label: showLabel)),
                      _handle(BarEdge.end, grip),
                    ],
                  )
                : _face(label: showLabel),
          ),
        );
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: left,
              width: width,
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
