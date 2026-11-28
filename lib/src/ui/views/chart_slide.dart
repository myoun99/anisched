// The part day: a date area slid left by a fraction of a column, painted
// only, and the quick sideways drag that moves it.
part of 'chart.dart';

/// A date area of [window] slid left by [slide] (part of a day, 0..1):
/// the child is laid out [ChartWindow.days] columns wide at the scale of
/// [ChartWindow.shown] across this box, then painted and hit-tested
/// shifted and clipped. A change of [slide] repaints this box alone (its
/// own layer); nothing rebuilds and nothing is laid out again.
class DaySlide extends SingleChildRenderObjectWidget {
  const DaySlide({
    super.key,
    required this.window,
    this.slide,
    required super.child,
  });

  final ChartWindow window;

  /// Null: no slide (a month's fixed window).
  final ValueListenable<double>? slide;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDaySlide(window.days, window.shown, slide);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderDaySlide).update(
        window.days,
        window.shown,
        slide,
      );
}

class _RenderDaySlide extends RenderProxyBox {
  _RenderDaySlide(this._days, this._shown, this._slide);

  int _days;
  int _shown;
  ValueListenable<double>? _slide;

  void update(int days, int shown, ValueListenable<double>? slide) {
    if (days != _days || shown != _shown) {
      _days = days;
      _shown = shown;
      markNeedsLayout();
    }
    if (slide == _slide) return;
    if (attached) {
      _slide?.removeListener(markNeedsPaint);
      slide?.addListener(markNeedsPaint);
    }
    _slide = slide;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipRectLayer>();

  @override
  bool get isRepaintBoundary => true;

  double get _dx => -(_slide?.value ?? 0) * size.width / _shown;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _slide?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _slide?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    final c = child;
    final width = constraints.maxWidth;
    if (c == null || !width.isFinite) {
      super.performLayout();
      return;
    }
    final inner = width * _days / _shown;
    c.layout(
      constraints.copyWith(minWidth: inner, maxWidth: inner),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(width, c.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    final dx = _dx;
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(c, offset + Offset(dx, 0)),
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null || !(Offset.zero & size).contains(position)) return false;
    return result.addWithPaintOffset(
      offset: Offset(_dx, 0),
      position: position,
      hitTest: (result, p) => c.hitTest(result, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_dx, 0, 0, 1);
  }
}

/// Hands the board's [DaySlide] amount to its bars: a bar crossing the
/// visible edges cuts itself there.
class _SlideScope extends InheritedWidget {
  const _SlideScope({required this.slide, required super.child});

  final ValueListenable<double>? slide;

  @override
  bool updateShouldNotify(_SlideScope old) => old.slide != slide;
}

/// A sideways drag that starts at once: past a few pixels, when the
/// finger has gone more sideways than up or down, it takes the gesture —
/// before a vertical list's own slop is reached. Mostly-vertical moves are
/// left to the list. A finger that goes down left of [calmBefore] (a
/// chart's names, which open on a tap) waits for the screen's own slop:
/// a tap there drifts a few pixels and must stay a tap.
class QuickHorizontalDrag extends HorizontalDragGestureRecognizer {
  QuickHorizontalDrag({super.debugOwner});

  /// Left of this (local x) the drag starts only past the usual slop.
  double calmBefore = 0;

  bool _calm = false;

  /// Sideways pixels before the drag starts (a touch screen's own slop
  /// is 18).
  static const slop = 4.0;

  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved = Offset.zero;
    _calm = event.localPosition.dx < calmBefore;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _moved += event.delta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final dx = _moved.dx.abs();
    final s = computeHitSlop(pointerDeviceKind, gestureSettings);
    final need = _calm || s < slop ? s : slop;
    return dx > need && dx > _moved.dy.abs();
  }
}

/// [onStart], [onUpdate] and [onEnd] of a [QuickHorizontalDrag], measured
/// from where the finger went down (nothing lost to the slop).
Widget quickHorizontalDrag({
  Key? key,
  HitTestBehavior? behavior,
  GestureDragStartCallback? onStart,
  GestureDragUpdateCallback? onUpdate,
  GestureDragEndCallback? onEnd,
  GestureDragCancelCallback? onCancel,
  double calmBefore = 0,
  required Widget child,
}) => RawGestureDetector(
  key: key,
  behavior: behavior,
  gestures: {
    QuickHorizontalDrag:
        GestureRecognizerFactoryWithHandlers<QuickHorizontalDrag>(
          QuickHorizontalDrag.new,
          (r) {
            r
              ..calmBefore = calmBefore
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = onStart
              ..onUpdate = onUpdate
              ..onEnd = onEnd
              ..onCancel = onCancel;
          },
        ),
  },
  child: child,
);
