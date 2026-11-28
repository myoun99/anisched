import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpView(WidgetTester t, AppView view) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
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
  return store;
}

Finder byPrefix(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

/// The rows' keys top to bottom.
List<String> rowsOf(WidgetTester t, String prefix) {
  final rows = byPrefix(prefix).evaluate().toList()
    ..sort(
      (a, b) => t
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(t.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [
    for (final e in rows)
      (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
  ];
}

void main() {
  testWidgets('a timeline bar given later dates keeps its row', (t) async {
    await pumpView(t, AppView.timeline);
    final before = rowsOf(t, 'tl-label-');
    // The first row with a bar: push its deadline past every other one.
    final key = before.firstWhere(
      (k) => find.byKey(Key('tl-bar-$k')).evaluate().isNotEmpty,
    );
    final end = find.descendant(
      of: find.byKey(Key('tl-bar-$key')),
      matching: find.byKey(const Key('bar-end')),
    );
    await t.drag(end, const Offset(400, 0));
    await t.pump();
    await t.pump();
    expect(rowsOf(t, 'tl-label-'), before);
  });

  testWidgets('a work bar given other dates keeps its lane', (t) async {
    final store = await pumpView(t, AppView.work);
    final bars = byPrefix('work-bar-');
    // The top lane's bar.
    final key = 'work-bar-${rowsOf(t, 'work-bar-').first}';
    final rowsBefore = {
      for (final e in bars.evaluate())
        (e.widget.key! as ValueKey<String>).value: t
            .getTopLeft(find.byWidget(e.widget))
            .dy,
    };
    final end = find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byKey(const Key('bar-end')),
    );
    // Shrink it to its first day: auto placement would now pull a later
    // bar up into this lane.
    final bar = t.getSize(
      find
          .descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(bar.width, greaterThan(0));
    final planBefore = store.partGroups().map((g) => g.planEndAt).toList();
    await t.drag(end, Offset(-bar.width, 0));
    await t.pump();
    await t.pump();
    // The edit went through.
    expect(
      store.partGroups().map((g) => g.planEndAt).toList(),
      isNot(planBefore),
    );
    for (final e in byPrefix('work-bar-').evaluate()) {
      final k = (e.widget.key! as ValueKey<String>).value;
      expect(
        t.getTopLeft(find.byWidget(e.widget)).dy,
        rowsBefore[k],
        reason: '$k stays in its lane',
      );
    }
  });
}
