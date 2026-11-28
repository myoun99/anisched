import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/device_settings.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
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
      r.value = (year: false, month: true, weekday: true);
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
  test('a year or a month is one cell, split where it turns', () {
    // Dec 28 → Jan 6: two months, two years, ten days.
    final w = ChartWindow(DateTime.utc(2026, 12, 28), 10);
    expect(chartRuns(w, (d) => d.year * 12 + d.month), [(0, 4), (4, 10)]);
    expect(chartRuns(w, (d) => d.year), [(0, 4), (4, 10)]);
    final nov = ChartWindow(DateTime.utc(2026, 11, 2), 20);
    expect(chartRuns(nov, (d) => d.month), [(0, 20)], reason: 'one cell');
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
    expect(find.text('11월'), findsWidgets);
    // No month row in a band's ruler: the corner says it.
    final header = t.widget<ChartHeader>(find.byType(ChartHeader).first);
    expect(header.rows.month, isFalse);
    expect(header.rows.year, isFalse);
  });
}
