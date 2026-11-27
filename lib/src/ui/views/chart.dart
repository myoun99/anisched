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

/// Rest-day shading and today's line under a row or the header.
class ChartGrid extends StatelessWidget {
  const ChartGrid({
    super.key,
    required this.window,
    required this.today,
    required this.restWeekdays,
  });

  final ChartWindow window;
  final DateTime today;

  /// DateTime.weekday values (1 = Mon … 7 = Sun).
  final Set<int> restWeekdays;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CustomPaint(
      painter: _GridPainter(
        window: window,
        today: window.indexOf(today),
        rest: restWeekdays,
        shade: c.panelAlt,
        todayLine: Theme.of(context).colorScheme.error,
      ),
      size: Size.infinite,
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.window,
    required this.today,
    required this.rest,
    required this.shade,
    required this.todayLine,
  });

  final ChartWindow window;
  final int today;
  final Set<int> rest;
  final Color shade;
  final Color todayLine;

  @override
  void paint(Canvas canvas, Size size) {
    final dw = size.width / window.days;
    final fill = Paint()..color = shade;
    for (var i = 0; i < window.days; i++) {
      if (rest.contains(window.dayAt(i).weekday)) {
        canvas.drawRect(Rect.fromLTWH(i * dw, 0, dw, size.height), fill);
      }
    }
    if (today >= 0 && today < window.days) {
      final x = (today + 0.5) * dw;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = todayLine
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.window.start != window.start ||
      old.window.days != window.days ||
      old.today != today ||
      old.shade != shade ||
      old.rest.length != rest.length;
}

/// Month labels over day numbers.
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
    final t = window.indexOf(today);
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, box) {
          final dw = box.maxWidth / window.days;
          return Stack(
            children: [
              Positioned.fill(
                child: ChartGrid(
                  window: window,
                  today: today,
                  restWeekdays: restWeekdays,
                ),
              ),
              for (var i = 0; i < window.days; i++)
                if (i == 0 || window.dayAt(i).day == 1)
                  Positioned(
                    left: i * dw + 4,
                    top: 4,
                    child: Text(
                      monthName(window.dayAt(i).month),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              for (var i = 0; i < window.days; i++)
                if (_labelled(i, dw, t))
                  Positioned(
                    left: i * dw,
                    width: dw >= 16 ? dw : 22,
                    top: 22,
                    child: Text(
                      '${window.dayAt(i).day}',
                      textAlign: dw >= 16 ? TextAlign.center : TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 11,
                        color: i == t
                            ? Theme.of(context).colorScheme.error
                            : restWeekdays.contains(window.dayAt(i).weekday)
                            ? c.faint
                            : c.muted,
                        fontWeight: i == t ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

extension on ChartHeader {
  /// Narrow days keep a number only on Mondays (and today), so the
  /// numbers never run together when zoomed out.
  bool _labelled(int i, double dw, int today) {
    if (dw >= 16) return true;
    final d = window.dayAt(i);
    if (i == today) return true;
    if ((i - today).abs() < (dw >= 8 ? 2 : 4)) return false;
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
}

/// Which end of a bar a drag moves.
enum BarEdge { start, end }

/// A date bar inside a row: [start]..[end] (days, both included). Its two
/// ends can be dragged; the bar previews the new dates while dragging and
/// reports them once on release through [onDates].
class ChartBar extends StatefulWidget {
  const ChartBar({
    super.key,
    required this.window,
    required this.start,
    required this.end,
    required this.color,
    this.label,
    this.textColor,
    this.top = 0,
    this.height = 16,
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
  final double top;
  final double height;
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

  (DateTime, DateTime) _dates(double dayWidth) {
    final s = chartDay(widget.start);
    final e = chartDay(widget.end);
    if (_edge == null) return (s, e);
    final d = Duration(days: (_dx / dayWidth).round());
    return switch (_edge!) {
      BarEdge.start => (s.add(d).isAfter(e) ? e : s.add(d), e),
      BarEdge.end => (s, e.add(d).isBefore(s) ? s : e.add(d)),
    };
  }

  Widget _handle(BarEdge edge, double dayWidth, double handle) =>
      GestureDetector(
        key: Key('bar-${edge.name}'),
        behavior: HitTestBehavior.opaque,
        // Measured from where the finger went down, so nothing is lost
        // while the date area's own drag competes for the gesture.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (d) => setState(() {
          _edge = edge;
          _from = d.globalPosition.dx;
          _dx = 0;
        }),
        onHorizontalDragUpdate: (d) =>
            setState(() => _dx = d.globalPosition.dx - _from),
        onHorizontalDragEnd: (_) {
          final (s, e) = _dates(dayWidth);
          setState(() => _edge = null);
          widget.onDates?.call(s, e);
        },
        onHorizontalDragCancel: () => setState(() => _edge = null),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: SizedBox(width: handle),
        ),
      );

  Widget _face() {
    final face = SizedBox.expand(
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
    );
    return widget.wrapBody?.call(face) ?? face;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final dw = box.maxWidth / widget.window.days;
        final (s, e) = _dates(dw);
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
              top: widget.top,
              height: widget.height,
              child: Opacity(
                opacity: widget.faded ? 0.35 : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(4),
                    border: _edge == null
                        ? null
                        : Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.onDates != null)
                        _handle(BarEdge.start, dw, handle),
                      Expanded(child: _face()),
                      if (widget.onDates != null)
                        _handle(BarEdge.end, dw, handle),
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
