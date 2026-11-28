// Moving the days: the viewport's drags, wheel and keys, the toolbar's today
// and zoom.
part of 'chart.dart';

/// Lets the date area be dragged sideways (empty space only: bars keep
/// their own drags), scrolled with a wheel or trackpad, and zoomed with a
/// pinch or Ctrl + wheel. Updates [chartView] by the pixel — no stepping
/// a day at a time — and a flick carries on as a list's does (the
/// platform's own scroll physics); a touch stops it. The chart redraws
/// only the days in view.
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

class _ChartViewportState extends State<ChartViewport>
    with SingleTickerProviderStateMixin {
  double _width = 1;
  late final _fling = AnimationController.unbounded(vsync: this)
    ..addListener(_flingTick);
  double _flung = 0;
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
    _fling.dispose();
    super.dispose();
  }

  void _pan(double dx) {
    if (dx == 0) return;
    chartView.value = chartView.value.scrolled(-dx / _dayWidth);
  }

  /// Carries a flick on: the platform's scroll physics over an endless
  /// extent, its offset fed to [_pan] frame by frame.
  void _flingFrom(double velocity) {
    final physics = ScrollConfiguration.of(context).getScrollPhysics(context);
    final sim = physics.createBallisticSimulation(
      FixedScrollMetrics(
        minScrollExtent: double.negativeInfinity,
        maxScrollExtent: double.infinity,
        pixels: 0,
        viewportDimension: _width,
        axisDirection: AxisDirection.right,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      -velocity,
    );
    if (sim == null) return;
    _flung = 0;
    _fling.animateWith(sim);
  }

  void _flingTick() {
    final v = _fling.value;
    _pan(-(v - _flung));
    _flung = v;
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
            _fling.stop();
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
          child: quickHorizontalDrag(
            behavior: HitTestBehavior.translucent,
            calmBefore: widget.labelWidth,
            onUpdate: (d) {
              if (_pointers.length < 2 && !_space) _pan(d.delta.dx);
            },
            onEnd: (d) {
              if (_pointers.isEmpty && !_space) {
                _flingFrom(d.velocity.pixelsPerSecond.dx);
              }
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
        icon: Icons.today,
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
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: c.panel,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(8),
              ),
              // The zoom icon alone: press and drag (Anicel's rule).
              child: Icon(Icons.zoom_in, size: 20, color: c.muted),
            ),
          ),
        ),
      ),
    );
  }
}
