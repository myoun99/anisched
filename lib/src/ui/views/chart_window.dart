// The days a chart shows: the window, the shared view (scroll and zoom), and
// the listenables the boards follow.
part of 'chart.dart';

/// The days a chart draws: [days] columns from [start], of which [shown]
/// fit the width at once. A running window draws one spare column past
/// the right edge, so a part-day scroll slides it in ([DaySlide]).
@immutable
class ChartWindow {
  const ChartWindow(this.start, this.days, {int? shown})
    : shown = shown ?? days;

  /// Today placed about a third in from the left, scrolled by [shift]
  /// whole days; [days] columns (zoom), or a count by size when null.
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

  /// The window for the shared [view] at [size]: its whole days, plus
  /// the spare column the part day slides in.
  factory ChartWindow.of(DateTime now, SizeClass size, ChartView view) {
    final w = ChartWindow.around(
      now,
      size,
      shift: view.shift.floor(),
      days: view.days,
    );
    return ChartWindow(w.start, w.days + 1, shown: w.days);
  }

  final DateTime start;
  final int days;

  /// Columns across the width (the scale); [days] may hold a spare one.
  final int shown;

  /// Column of [t] (may fall outside 0..days-1).
  int indexOf(DateTime t) => chartDay(t).difference(start).inDays;

  DateTime dayAt(int i) => start.add(Duration(days: i));

  @override
  bool operator ==(Object other) =>
      other is ChartWindow &&
      other.start == start &&
      other.days == days &&
      other.shown == shown;

  @override
  int get hashCode => Object.hash(start, days, shown);
}

/// Where the date area is scrolled to and how far it is zoomed, shared by
/// the timeline and the work view and kept while the app runs.
@immutable
class ChartView {
  const ChartView({this.shift = 0, this.days});

  /// Days scrolled from the default position (negative = the past),
  /// part days included: a drag moves it by the pixel.
  final double shift;

  /// The part of a day past [shift]'s whole days, 0 ≤ slide < 1.
  double get slide => shift - shift.floor();

  /// Days shown; null = the default for the screen size.
  final int? days;

  static const zoomSteps = [7, 10, 14, 21, 28, 35, 49, 70, 105];
  static const minDays = 7;
  static const maxDays = 105;

  ChartView scrolled(double by) => ChartView(shift: shift + by, days: days);

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

/// The running view's days: [chartView] over today at a size, as one
/// listenable a [ChartBoard]'s date parts follow (the views no longer
/// rebuild for a scroll or a zoom). It changes only when a whole day
/// comes or goes; the part day in between is [slide], which repaints
/// the date areas and rebuilds nothing.
class RunningWindow extends ChangeNotifier
    implements ValueListenable<ChartWindow> {
  RunningWindow(this._now, this._size) {
    chartView.addListener(_moved);
    _value = _compute();
    slide.value = chartView.value.slide;
  }

  /// The part of a day scrolled past the window's start, 0 ≤ slide < 1.
  final slide = ValueNotifier<double>(0);

  DateTime _now;
  SizeClass _size;
  late ChartWindow _value;

  ChartWindow _compute() => ChartWindow.of(_now, _size, chartView.value);

  @override
  ChartWindow get value => _value;

  void _moved() {
    slide.value = chartView.value.slide;
    final next = _compute();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// Today or the screen size changed (the view's own rebuild).
  void update(DateTime now, SizeClass size) {
    _now = now;
    _size = size;
    _moved();
  }

  @override
  void dispose() {
    chartView.removeListener(_moved);
    slide.dispose();
    super.dispose();
  }
}

/// A window that never moves: one month of the month view.
class FixedWindow implements ValueListenable<ChartWindow> {
  const FixedWindow(this.value);

  @override
  final ChartWindow value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
