import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../theme.dart';
import '../widgets.dart';

/// Local calendar day as a UTC midnight, so day differences are exact.
DateTime chartDay(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  return DateTime.utc(l.year, l.month, l.day);
}

/// The days a chart shows: [days] columns from [start].
class ChartWindow {
  const ChartWindow(this.start, this.days);

  /// Today placed a little after the left edge, the column count by size.
  factory ChartWindow.around(DateTime now, SizeClass size, {int shift = 0}) {
    final (days, before) = switch (size) {
      SizeClass.wide => (35, 11),
      SizeClass.medium => (24, 7),
      SizeClass.narrow => (10, 3),
    };
    final today = chartDay(now);
    return ChartWindow(today.add(Duration(days: shift - before)), days);
  }

  final DateTime start;
  final int days;

  /// Column of [t] (may fall outside 0..days-1).
  int indexOf(DateTime t) => chartDay(t).difference(start).inDays;

  DateTime dayAt(int i) => start.add(Duration(days: i));
}

/// Toolbar paging buttons: 「◀ 오늘 ▶」.
class ChartPager extends StatelessWidget {
  const ChartPager({super.key, required this.onShift, required this.onToday});

  final ValueChanged<int> onShift;
  final VoidCallback onToday;

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
        label: '오늘',
        selected: false,
        onTap: onToday,
      ),
      _IconFace(
        key: const Key('chart-next'),
        icon: Icons.chevron_right,
        onTap: () => onShift(7),
      ),
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
                      '${window.dayAt(i).month}월',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              for (var i = 0; i < window.days; i++)
                Positioned(
                  left: i * dw,
                  width: dw,
                  top: 22,
                  child: Text(
                    '${window.dayAt(i).day}',
                    textAlign: TextAlign.center,
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
        onHorizontalDragStart: (_) => setState(() {
          _edge = edge;
          _dx = 0;
        }),
        onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
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
