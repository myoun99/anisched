import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<void> pumpView(WidgetTester t, AppView view) async {
  t.view.physicalSize = const Size(1280, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(() => chartMonthView.value = false);
  chartView.value = const ChartView();
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: view,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
}

void main() {
  test('a month\'s window runs from the 1st to its last day', () {
    final feb = monthWindow(DateTime(2028, 2, 17));
    expect(feb.days, 29);
    expect((feb.start.month, feb.start.day), (2, 1));
    expect(monthWindow(DateTime(2026, 11)).days, 30);
  });

  testWidgets('a bar into the next month is cut there and goes on below', (
    t,
  ) async {
    await pumpView(t, AppView.timeline);
    expect(find.byKey(const Key('month-stack')), findsNothing);
    await t.tap(find.byKey(const Key('chart-month')));
    await t.pump();
    expect(find.byKey(const Key('month-stack')), findsOneWidget);
    // No zoom in the month view.
    expect(find.byKey(const Key('chart-zoom')), findsNothing);
    final nov = find.byKey(const Key('month-2026-11'));
    final dec = find.byKey(const Key('month-2026-12'));
    expect(nov, findsOneWidget);
    expect(dec, findsOneWidget);
    // The work due 12/3 runs from November: cut at November's end, and
    // again at December's start; its true ends keep their grips.
    expect(
      find.descendant(of: nov, matching: find.byKey(const Key('bar-cut-end'))),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: dec,
        matching: find.byKey(const Key('bar-cut-start')),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(of: dec, matching: find.byKey(const Key('bar-end'))),
      findsWidgets,
    );
    // Each month lists only the rows with work in it.
    final novRows = find.descendant(
      of: nov,
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('tl-label-'),
      ),
    );
    final decRows = find.descendant(
      of: dec,
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('tl-label-'),
      ),
    );
    expect(novRows.evaluate().length, greaterThan(decRows.evaluate().length));
    // And back.
    await t.tap(find.byKey(const Key('chart-month')));
    await t.pump();
    expect(find.byKey(const Key('month-stack')), findsNothing);
  });

  testWidgets('the work tab has the month view too', (t) async {
    await pumpView(t, AppView.work);
    await t.tap(find.byKey(const Key('chart-month')));
    await t.pump();
    expect(find.byKey(const Key('month-2026-11')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('month-2026-11')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('work-bar-'),
        ),
      ),
      findsWidgets,
    );
  });
}
