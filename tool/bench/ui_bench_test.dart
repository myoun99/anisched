// UI performance numbers, re-runnable, not part of `flutter test` (it
// only runs test/). Run:
//   flutter test tool/bench/ui_bench_test.dart
// Prints one table: per scenario, wall time per frame (debug build in the
// test harness — compare before/after, not absolute), widgets rebuilt per
// frame (debugOnRebuildDirtyWidget), bar builds and chart paints.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/sample_data.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 27, 14);

/// The example catalogue [copies] times, a week apart: a big document.
CatalogueStore bigCatalogue(int copies) {
  final store = CatalogueStore(openAppDatabase(':memory:'), clock: () => now);
  for (var i = 0; i < copies; i++) {
    fillSample(store, now.add(Duration(days: 7 * (i - copies ~/ 2))));
  }
  return store;
}

int _rebuilds = 0;

final rows = <String>[];

Future<void> measure(
  WidgetTester t,
  String name,
  int frames,
  Future<void> Function(int i) frame,
) async {
  ChartPaints.reset();
  _rebuilds = 0;
  final sw = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    await frame(i);
  }
  sw.stop();
  rows.add(
    '| $name | $frames | ${(sw.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} ms '
    '| ${(_rebuilds / frames).toStringAsFixed(0)} '
    '| ${(ChartPaints.barBuilds / frames).toStringAsFixed(1)} '
    '| ${ChartPaints.background}/${ChartPaints.today}/${ChartPaints.preview} |',
  );
}

Future<CatalogueStore> pumpApp(
  WidgetTester t,
  AppView view, {
  int copies = 30,
  Size size = const Size(1280, 800),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  chartView.value = const ChartView();
  chartMonthView.value = false;
  final store = bigCatalogue(copies);
  final sw = Stopwatch()..start();
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: view,
        reader: SyncCatalogueReader(store),
        store: store,
        timer: WorkTimerStore(store.db, clock: () => now),
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  await t.pump();
  sw.stop();
  rows.add(
    '| first frames (${view.name}, ${store.partGroups().length} units) | 1 | '
    '${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms | | | |',
  );
  return store;
}

Finder byPrefix(String p) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(p),
);

void main() {
  setUp(() {
    debugOnRebuildDirtyWidget = (e, builtOnce) => _rebuilds++;
  });
  tearDown(() => debugOnRebuildDirtyWidget = null);
  tearDownAll(() {
    debugPrint(
      '\n| scenario | frames | ms/frame | rebuilds/frame | bar builds/frame '
      '| paints bg/today/preview |\n|---|---|---|---|---|---|\n'
      '${rows.join('\n')}',
    );
  });

  testWidgets('timeline', (t) async {
    await pumpApp(t, AppView.timeline);
    // Rows down to the first bar in view (the top ones are overdue).
    final rowsList = find
        .descendant(
          of: find.byType(ChartBoard),
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < 40; i++) {
      if (find
          .byKey(const Key('bar-end'))
          .hitTestable()
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await t.drag(rowsList, const Offset(0, -200));
      await t.pump();
    }
    await t.pump();
    final end = find.byKey(const Key('bar-end')).hitTestable().first;
    final g = await t.startGesture(t.getCenter(end));
    await measure(t, 'timeline: drag bar end (per move)', 20, (i) async {
      await g.moveBy(const Offset(6, 0));
      await t.pump();
    });
    await g.up();
    await t.pump();
    final list = find
        .descendant(
          of: find.byType(ChartBoard),
          matching: find.byType(Scrollable),
        )
        .first;
    await measure(t, 'timeline: scroll rows', 20, (i) async {
      await t.drag(list, const Offset(0, -40));
      await t.pump();
    });
    await measure(t, 'timeline: scroll days', 20, (i) async {
      chartView.value = chartView.value.scrolled(1);
      await t.pump();
    });
    await measure(t, 'timeline: zoom', 6, (i) async {
      chartView.value = chartView.value.stepped(
        chartView.value.days ?? 35,
        zoomIn: i.isEven,
      );
      await t.pump();
    });
  });

  testWidgets('work', (t) async {
    await pumpApp(t, AppView.work);
    await measure(t, 'work: scroll days', 20, (i) async {
      chartView.value = chartView.value.scrolled(1);
      await t.pump();
    });
    final end = find.byKey(const Key('bar-end')).first;
    final g = await t.startGesture(t.getCenter(end));
    await measure(t, 'work: drag bar end (per move)', 20, (i) async {
      await g.moveBy(const Offset(6, 0));
      await t.pump();
    });
    await g.up();
    await t.pump();
  });

  testWidgets('list', (t) async {
    await pumpApp(t, AppView.list);
    final list = find.byKey(const Key('sheet-rows'));
    await measure(t, 'list: scroll', 20, (i) async {
      await t.drag(list, const Offset(0, -60));
      await t.pump();
    });
    await measure(t, 'list: open/close a line', 6, (i) async {
      await t.tap(byPrefix('line-').first);
      await t.pump();
    });
  });

  testWidgets('month view', (t) async {
    chartMonthView.value = true;
    addTearDown(() => chartMonthView.value = false);
    await pumpApp(t, AppView.timeline);
    chartMonthView.value = true;
    await t.pump();
    final stack = find.byKey(const Key('month-stack'));
    expect(stack, findsOneWidget);
    final first = byPrefix('month-').first;
    final y0 = t.getTopLeft(first).dy;
    await measure(t, 'months: scroll', 20, (i) async {
      await t.drag(stack, const Offset(0, -80));
      await t.pump();
    });
    debugPrint(
      'months scrolled ${y0 - t.getTopLeft(byPrefix('month-').first).dy}',
    );
  });

  testWidgets('timer tick', (t) async {
    await pumpApp(t, AppView.timeline);
    // The bar's clock ticks every second: what does a tick rebuild?
    await measure(t, 'idle second (timer clock)', 5, (i) async {
      await t.pump(const Duration(seconds: 1));
    });
  });

  test('size', () {
    expect(kDebugMode, isTrue);
  });
}
