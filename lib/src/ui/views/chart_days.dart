// What the days look like: numbered stretches, days off and holidays, the
// background, today and the date ruler.
part of 'chart.dart';

/// Which day columns carry a number and how the stripes run: every
/// [step] days, the step the smallest that leaves a number its real width.
/// Anchored to the calendar, not the window, so scrolling never moves which
/// days are numbered. Steps under a week count days; a week or more starts
/// on Mondays.
@immutable
class DayLabels {
  DayLabels(this.window, this.dayWidth, double numberWidth)
    : need = numberWidth,
      step = _steps.firstWhere(
        (k) => numberFits(numberWidth, dayWidth * k),
        orElse: () => _steps.last,
      );

  static const _steps = [1, 2, 3, 7, 14, 28];

  final ChartWindow window;
  final double dayWidth;

  /// Pixels the widest number takes unsqueezed.
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

/// Whether a day's number (or a weekday's letter) [width] wide fits a
/// cell [room] wide under the app's fitting rule ([fitWord]: letter gaps
/// first, then down to 70% wide). Only when it does not are days stepped
/// over — never for zoom alone. The one test every day label goes by.
bool numberFits(double width, double room) =>
    !fitWord(width: width, gaps: 1, room: room).cut;

/// How wide a day number is drawn: the widest two digits at the header's
/// size.
double chartNumberWidth(BuildContext context) {
  final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 11);
  return (TextPainter(
    text: TextSpan(text: '30', style: style),
    textDirection: TextDirection.ltr,
  )..layout()).width;
}

/// What a day is to the chart's background and header.
enum DayKind { plain, rest, off, holiday }

/// The days a chart marks: the usual rest weekdays, the user's own days
/// off and public holidays (by UTC midnight, with their names). One rule
/// for every chart's background and header: a day off wins over a
/// holiday, a holiday over a rest weekday.
@immutable
class ChartDays {
  const ChartDays({
    this.restWeekdays = const {DateTime.saturday, DateTime.sunday},
    this.daysOff = const [],
    this.holidays = const {},
    this.events = const [],
  });

  final Set<int> restWeekdays;
  final List<DaysOff> daysOff;
  final Map<DateTime, String> holidays;

  /// Events on no episode (the date ruler's): days off and the user's
  /// own dated notes, titled on the ruler.
  final List<EventRow> events;

  /// The ruler's events on [day].
  List<EventRow> eventsOn(DateTime day) => [
    for (final e in events)
      if (e.date.year == day.year &&
          e.date.month == day.month &&
          e.date.day == day.day)
        e,
  ];

  static DateTime _key(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  DayKind kindOf(DateTime day) {
    if (daysOff.any((o) => o.contains(day))) return DayKind.off;
    if (holidays.containsKey(_key(day))) return DayKind.holiday;
    if (restWeekdays.contains(day.weekday)) return DayKind.rest;
    return DayKind.plain;
  }

  /// The holiday's name on [day], if it is one.
  String? holidayName(DateTime day) => holidays[_key(day)];

  @override
  bool operator ==(Object other) =>
      other is ChartDays &&
      setEquals(other.restWeekdays, restWeekdays) &&
      listEquals(
        [for (final o in other.daysOff) (o.start, o.end)],
        [for (final o in daysOff) (o.start, o.end)],
      ) &&
      mapEquals(other.holidays, holidays) &&
      listEquals(other.events, events);

  @override
  int get hashCode =>
      Object.hash(restWeekdays.length, daysOff.length, holidays.length);
}

/// Marked days' colours: their numbers, and (faintly) their columns —
/// one colour for every kind of day off (the user's rule).
Map<DayKind, Color> dayMarkColors(BuildContext context) {
  final c = AppColors.of(context);
  return {
    DayKind.rest: c.restDay,
    DayKind.off: c.restDay,
    DayKind.holiday: c.restDay,
  };
}

/// The bands' grey: barely there, enough to count days by.
Color chartStripe(BuildContext context) {
  final c = AppColors.of(context);
  return Color.lerp(c.panel, c.line, 0.14)!;
}

/// How strongly a marked day's colour washes its column.
double chartMarkAlpha(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? 0.13 : 0.075;

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
    required this.days,
    required this.stripe,
    required this.wash,
    required this.numberWidth,
  });

  final ChartWindow window;
  final ChartDays days;

  /// Every other numbered stretch (Excel-like bands).
  final Color stripe;

  /// Marked days' washes, over the bands.
  final Map<DayKind, Color> wash;
  final double numberWidth;

  @override
  void paint(Canvas canvas, Size size) {
    ChartPaints.background++;
    final dw = size.width / window.days;
    final labels = DayLabels(window, dw, numberWidth);
    final band = Paint()..color = stripe;
    for (var i = 0; i < window.days; i++) {
      final r = Rect.fromLTWH(i * dw, 0, dw, size.height);
      if (labels.shaded(i)) canvas.drawRect(r, band);
      if (wash[days.kindOf(window.dayAt(i))] case final w?) {
        canvas.drawRect(r, Paint()..color = w);
      }
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.window != window ||
      old.stripe != stripe ||
      !mapEquals(old.wash, wash) ||
      old.numberWidth != numberWidth ||
      old.days != days;
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
    required this.days,
  });

  final ChartWindow window;
  final DateTime today;
  final ChartDays days;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _BackgroundPainter(
              window: window,
              days: days,
              stripe: chartStripe(context),
              wash: {
                for (final e in dayMarkColors(context).entries)
                  e.key: e.value.withValues(alpha: chartMarkAlpha(context)),
              },
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
    this.days = const ChartDays(),
    this.onDayLongPress,
    this.onEvent,
  });

  final ChartWindow window;
  final DateTime today;
  final ChartDays days;

  /// A long press on a day of the ruler: a new event of no episode there
  /// (a day off, a note); null leaves the ruler read-only.
  final ValueChanged<DateTime>? onDayLongPress;

  /// A ruler event tapped: edit or remove it.
  final ValueChanged<EventRow>? onEvent;

  /// The header's height: month, day numbers, and the line of names.
  static const height = 58.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = DefaultTextStyle.of(context).style;
    final slide = context.getInheritedWidgetOfExactType<_SlideScope>()?.slide;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DayLayers(window: window, today: today, days: days),
          RepaintBoundary(
            child: CustomPaint(
              painter: _HeaderPainter(
                window: window,
                today: window.indexOf(today),
                days: days,
                marks: dayMarkColors(context),
                ink: style.color ?? c.muted,
                muted: c.muted,
                faint: c.faint,
                red: Theme.of(context).colorScheme.error,
                style: style,
                lang: appLang.value,
                numberWidth: chartNumberWidth(context),
                pinned: slide != null,
              ),
            ),
          ),
          if (slide != null)
            RepaintBoundary(
              child: CustomPaint(
                painter: _MonthPin(
                  window: window,
                  slide: slide,
                  ink: style.color ?? c.muted,
                  style: style,
                  lang: appLang.value,
                ),
              ),
            ),
          // The ruler's long press, and its names: a holiday's, the
          // events' titles — small, under the day number.
          LayoutBuilder(
            builder: (context, box) {
              final dw = box.maxWidth / window.days;
              return Stack(
                children: [
                  if (onDayLongPress case final press?)
                    Positioned.fill(
                      child: GestureDetector(
                        key: const Key('ruler-press'),
                        behavior: HitTestBehavior.translucent,
                        onLongPressStart: (d) {
                          final i = (d.localPosition.dx / dw).floor();
                          press(window.dayAt(i.clamp(0, window.days - 1)));
                        },
                      ),
                    ),
                  for (var i = 0; i < window.days; i++)
                    if (_RulerNote.of(days, window.dayAt(i)) case final n?)
                      Positioned(
                        left: i * dw,
                        width: (dw > 56.0 ? dw : 56.0).clamp(
                          0.0,
                          box.maxWidth - i * dw,
                        ),
                        top: 40,
                        height: 16,
                        child: _RulerNote(
                          key: Key('ruler-$i'),
                          note: n,
                          // A day off's words in its colour; a note muted.
                          color:
                              n.holiday != null || n.events.any((e) => e.rest)
                              ? c.restDay
                              : c.muted,
                          onEvent: onEvent,
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// What the ruler says on a day: a holiday's name, the day's events.
typedef _Note = ({String? holiday, List<EventRow> events});

/// A day's small line on the ruler: its holiday and event titles in one
/// line (condensed, the whole on hover / long press). A tap edits the
/// first event; a holiday alone only shows its name.
class _RulerNote extends StatelessWidget {
  const _RulerNote({
    super.key,
    required this.note,
    required this.color,
    this.onEvent,
  });

  final _Note note;
  final Color color;
  final ValueChanged<EventRow>? onEvent;

  static _Note? of(ChartDays days, DateTime day) {
    final holiday = days.holidayName(day);
    final events = days.eventsOn(day);
    if (holiday == null && events.isEmpty) return null;
    return (holiday: holiday, events: events);
  }

  @override
  Widget build(BuildContext context) {
    final words = [
      ?note.holiday,
      for (final e in note.events) e.title,
    ].join(' · ');
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FitText(
        words,
        style: TextStyle(
          fontSize: 10,
          height: 1.4,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final first = note.events.firstOrNull;
    if (first == null || onEvent == null) {
      return Tooltip(message: words, child: text);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onEvent!(first),
      child: text,
    );
  }
}

class _HeaderPainter extends CustomPainter {
  _HeaderPainter({
    required this.window,
    required this.today,
    required this.days,
    required this.marks,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.red,
    required this.style,
    required this.lang,
    required this.numberWidth,
    this.pinned = false,
  });

  /// The first month's name is drawn by [_MonthPin] instead.
  final bool pinned;
  final double numberWidth;
  final ChartWindow window;
  final int today;
  final ChartDays days;

  /// The numbers' colours for marked days.
  final Map<DayKind, Color> marks;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color red;
  final TextStyle style;
  final Lang lang;

  TextPainter _text(
    String s,
    Color color, {
    bool bold = false,
    double spacing = 0,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: style.copyWith(
        fontSize: 11,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: spacing == 0 ? null : spacing,
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
      if ((i == 0 && !pinned) || d.day == 1) {
        _text(
          monthName(d.month, lang),
          ink,
          bold: true,
        ).paint(canvas, Offset(i * dw + 4, 4));
      }
      // Every day's number when it fits its cell (squeezed if need be);
      // else one where its stretch starts (and today's, always), none so
      // near today that the two would touch.
      final every = labels.step == 1;
      final near = !every && i != today && (i - today).abs() * dw < labels.need;
      if (i != today && (!labels.labelled(i) || near)) continue;
      final text = '${d.day}';
      final color = i == today ? red : (marks[days.kindOf(d)] ?? muted);
      var t = _text(text, color, bold: i == today);
      if (!every) {
        t.paint(canvas, Offset(i * dw + 2, 24));
        continue;
      }
      // In its cell: letter gaps, then narrower, as FitText does.
      final fit = fitWord(width: t.width, gaps: text.length - 1, room: dw);
      if (fit.spacing != 0) {
        t = _text(text, color, bold: i == today, spacing: fit.spacing);
      }
      final w = t.width * fit.scaleX;
      canvas
        ..save()
        ..translate(i * dw + (dw - w) / 2, 24)
        ..scale(fit.scaleX, 1);
      t.paint(canvas, Offset.zero);
      canvas.restore();
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
      old.pinned != pinned ||
      !mapEquals(old.marks, marks) ||
      old.days != days;
}

/// The month name at the visible left edge of a sliding header: it stays
/// in sight as the part day slides (the first column goes under the
/// edge), pushed out by the next month's name as that comes in. Its own
/// layer, repainting with the slide alone.
class _MonthPin extends CustomPainter {
  _MonthPin({
    required this.window,
    required this.slide,
    required this.ink,
    required this.style,
    required this.lang,
  }) : super(repaint: slide);

  final ChartWindow window;
  final ValueListenable<double> slide;
  final Color ink;
  final TextStyle style;
  final Lang lang;

  @override
  void paint(Canvas canvas, Size size) {
    final dw = size.width / window.days;
    final t = TextPainter(
      text: TextSpan(
        text: monthName(window.start.month, lang),
        style: style.copyWith(
          fontSize: 11,
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var x = slide.value * dw + 4;
    for (var i = 1; i < window.days; i++) {
      if (window.dayAt(i).day != 1) continue;
      final next = i * dw + 4;
      if (x + t.width + 6 > next) x = next - t.width - 6;
      break;
    }
    t.paint(canvas, Offset(x, 4));
  }

  @override
  bool shouldRepaint(_MonthPin old) =>
      old.window != window ||
      old.slide != slide ||
      old.ink != ink ||
      old.lang != lang;
}
