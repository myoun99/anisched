import 'dart:typed_data';

import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/device_settings.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<void> pumpTimeline(WidgetTester t) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  chartView.value = const ChartView();
  addTearDown(() {
    chartMonthView.value = false;
    for (final r in rulerRows.values) {
      r.value = defaultRulerRows;
    }
  });
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: AppView.timeline,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
}

void main() {
  colourTests();
  test('a month (a year) is one merged cell: all its days, past the edges', () {
    // Dec 28 → Jan 6: two months, two years, ten days.
    final w = ChartWindow(DateTime.utc(2026, 12, 28), 10);
    final months = spanCells(
      w,
      (d) => DateTime(d.year, d.month),
      (d) => DateTime(d.year, d.month + 1),
    );
    expect([for (final c in months) (c.from, c.to)], [(-27, 4), (4, 35)]);
    // One cell = the month's days × the column.
    for (final (c, days) in [(months[0], 31), (months[1], 31)]) {
      expect(c.to - c.from, days);
    }
    final years = spanCells(
      w,
      (d) => DateTime(d.year),
      (d) => DateTime(d.year + 1),
    );
    expect([for (final c in years) c.to - c.from], [365, 365]);
    expect(years[1].from, 4);
    final feb = ChartWindow(DateTime.utc(2027, 2, 10), 5);
    final one = spanCells(
      feb,
      (d) => DateTime(d.year, d.month),
      (d) => DateTime(d.year, d.month + 1),
    );
    expect(one.single.to - one.single.from, 28, reason: 'one cell');
  });

  test('rows go year, month, days, weekdays, events; hidden ones fold', () {
    final all = ChartHeader.layout((year: true, month: true, weekday: true));
    expect(all.year < all.month, isTrue);
    expect(all.month < all.date, isTrue);
    expect(all.date < all.weekday, isTrue);
    expect(all.weekday < all.note, isTrue);
    final days = ChartHeader.layout((
      year: false,
      month: false,
      weekday: false,
    ));
    expect(days.date, all.year, reason: 'the days move up to the top');
    expect(days.height, lessThan(all.height));
  });

  testWidgets('a switch in the tab\'s ruler menu hides that row', (t) async {
    await pumpTimeline(t);
    double height() => t.getSize(find.byType(ChartHeader).first).height;
    final before = height();
    await t.tap(find.byKey(const Key('ruler-rows')));
    await t.pump();
    await t.tap(find.byKey(const Key('ruler-row-weekday')));
    await t.pump();
    expect(rulerRows[RulerTab.timeline]!.value.weekday, isFalse);
    expect(rulerRows[RulerTab.work]!.value.weekday, isTrue, reason: 'per tab');
    await t.pump();
    expect(height(), before - ChartHeader.weekdayRow);
  });

  testWidgets('each month band names its month over its row names', (t) async {
    await pumpTimeline(t);
    chartMonthView.value = true;
    await t.pump();
    expect(find.byKey(const Key('month-corner-2026-11')), findsOneWidget);
    expect(find.textContaining('11월'), findsWidgets);
    // No month row in a band's ruler: the corner says it.
    final header = t.widget<ChartHeader>(find.byType(ChartHeader).first);
    expect(header.rows.month, isFalse);
    expect(header.rows.year, isFalse);
  });
}

/// The colour at [x], [y] of an image's RGBA bytes, as 0xAARRGGBB.
int pixel(ByteData bytes, int width, int x, int y) {
  final o = (y * width + x) * 4;
  return bytes.getUint8(o + 3) << 24 |
      bytes.getUint8(o) << 16 |
      bytes.getUint8(o + 1) << 8 |
      bytes.getUint8(o + 2);
}

void colourTests() {
  testWidgets('a day off is its own colour, band or not; merged rows plain', (
    t,
  ) async {
    const width = 1400.0;
    t.view.physicalSize = const Size(width, 300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Two weeks from Monday Nov 2: four weekend days, wide columns.
    final window = ChartWindow(DateTime.utc(2026, 11, 2), 14);
    final boundary = GlobalKey();
    late Map<DayKind, Color> fills;
    late Color panel;
    late Color stripe;
    late double numberWidth;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            fills = chartDayFills(context);
            panel = AppColors.of(context).panel;
            stripe = chartStripe(context);
            numberWidth = chartNumberWidth(context);
            return Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                // The chart's own ground under the ruler.
                child: Container(
                  color: panel,
                  width: width,
                  child: ChartHeader(
                    window: window,
                    today: DateTime(2026, 10, 1),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final at = ChartHeader.layout(defaultRulerRows);
    final image = await t.runAsync(
      () =>
          (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(),
    );
    final bytes = (await t.runAsync(() => image!.toByteData()))!;
    final dw = width / window.days;
    // The events' line: nothing written there, only the day's ground.
    final y = (at.note + ChartHeader.noteRow - 2).round();
    for (var i = 0; i < window.days; i++) {
      final c = pixel(bytes, width.toInt(), (i * dw + 3).round(), y);
      final rest = window.dayAt(i).weekday >= DateTime.saturday;
      if (rest) {
        expect(
          c,
          fills[DayKind.rest]!.toARGB32(),
          reason: 'day $i: the day-off colour',
        );
      } else {
        expect(
          [panel.toARGB32(), stripe.toARGB32()],
          contains(c),
          reason: 'day $i: band or plain',
        );
      }
      // The month row: plain ground over every day, rest or band.
      final m = pixel(
        bytes,
        width.toInt(),
        (i * dw + 3).round(),
        at.month.round() + 1,
      );
      expect(m, panel.toARGB32(), reason: 'day $i: the merged month cell');
    }
    // A day off did fall on a band (where colours used to mix).
    final labels = DayLabels(window, dw, numberWidth);
    expect([
      for (var i = 0; i < window.days; i++)
        if (window.dayAt(i).weekday >= DateTime.saturday && labels.shaded(i)) i,
    ], isNotEmpty);
    // Both kinds of ground show.
    final grounds = {
      for (var i = 0; i < window.days; i++)
        if (window.dayAt(i).weekday < DateTime.saturday)
          pixel(bytes, width.toInt(), (i * dw + 3).round(), y),
    };
    expect(grounds, {panel.toARGB32(), stripe.toARGB32()});
  });

  testWidgets('a month\'s name sits at the centre of its merged cell', (
    t,
  ) async {
    const width = 1400.0;
    t.view.physicalSize = const Size(width, 300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Nov 26 for six weeks: December whole, columns 5 to 36.
    final window = ChartWindow(DateTime.utc(2026, 11, 26), 42);
    final boundary = GlobalKey();
    late Color panel;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            panel = AppColors.of(context).panel;
            return Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: Container(
                  color: panel,
                  width: width,
                  child: ChartHeader(
                    window: window,
                    today: DateTime(2026, 10, 1),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final at = ChartHeader.layout(defaultRulerRows);
    final image = await t.runAsync(
      () =>
          (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(),
    );
    final bytes = (await t.runAsync(() => image!.toByteData()))!;
    final dw = width / window.days;
    final cell = (from: 5 * dw, to: 36 * dw);
    // The ink of the row inside December's cell (its edge lines left out).
    final xs = <int>[];
    for (var x = cell.from.ceil() + 2; x < cell.to.floor() - 2; x++) {
      for (var y = at.month.round(); y < at.month + ChartHeader.spanRow; y++) {
        if (pixel(bytes, width.toInt(), x, y) != panel.toARGB32()) {
          xs.add(x);
          break;
        }
      }
    }
    expect(xs, isNotEmpty);
    final middle = (xs.first + xs.last) / 2;
    expect(middle, closeTo((cell.from + cell.to) / 2, 2));
  });
}
