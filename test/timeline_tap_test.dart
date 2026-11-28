import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<String> pumpTimeline(WidgetTester t) async {
  t.view.physicalSize = const Size(844, 390);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  chartView.value = const ChartView();
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
  return store.partGroups().first.key;
}

void main() {
  // A finger never lands still: a tap on a row's name that drifts a few
  // pixels sideways still opens the row (유저 2026-11-28, taps lost).
  for (final drift in const [Offset.zero, Offset(6, 0), Offset(10, 3)]) {
    testWidgets('a tap on a row\'s name drifting $drift opens it', (t) async {
      final key = await pumpTimeline(t);
      final label = find.byKey(Key('tl-label-$key')).first;
      final at = t.getCenter(label) - const Offset(40, 0);
      final gesture = await t.startGesture(at, kind: PointerDeviceKind.touch);
      await gesture.moveBy(drift);
      await gesture.up();
      await t.pump();
      await t.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('fold-cuts-'),
        ),
        findsWidgets,
        reason: 'the details opened',
      );
    });
  }

  // Past the usual slop a drag from the names still slides the chart.
  testWidgets('a long sideways drag from a row\'s name slides the chart', (
    t,
  ) async {
    final key = await pumpTimeline(t);
    final before = chartView.value;
    final label = find.byKey(Key('tl-label-$key')).first;
    await t.dragFrom(
      t.getCenter(label) - const Offset(40, 0),
      const Offset(-80, 0),
      touchSlopX: 0,
    );
    await t.pump();
    expect(chartView.value, isNot(before));
  });
}
