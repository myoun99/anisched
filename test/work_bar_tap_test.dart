import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<void> pumpWork(WidgetTester t, {AppView view = AppView.work}) async {
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
}

/// The work bars on screen, widest first: (key, the drawn bar's rect).
List<(String, Rect)> bars(WidgetTester t) {
  final out = <(String, Rect)>[];
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('work-bar-'),
          )
          .evaluate()) {
    final key = (e.widget.key! as ValueKey<String>).value.substring(
      'work-bar-'.length,
    );
    final tap = find.descendant(
      of: find.byWidget(e.widget),
      matching: find.byKey(const Key('bar-tap')),
    );
    if (tap.evaluate().isEmpty) continue;
    out.add((key, t.getRect(tap)));
  }
  return out..sort((a, b) => b.$2.width.compareTo(a.$2.width));
}

Finder details(String key) => find.byKey(Key('details-due-$key'));

/// A tap on the board off every bar: under the last lane.
Future<void> tapBlank(WidgetTester t) async {
  final board = t.getRect(find.byKey(const Key('work-blank')));
  await t.tapAt(Offset(board.center.dx, board.bottom - 12));
  await t.pump();
}

void main() {
  testWidgets('a tap anywhere on a bar opens it; off the bars closes', (
    t,
  ) async {
    await pumpWork(t);
    final (key, r) = bars(t).first;
    expect(r.width, greaterThan(60), reason: 'room for the five spots');
    for (final (name, x) in [
      ('left grip', r.left + 3),
      ('left end', r.left + 18),
      ('middle', r.center.dx),
      ('right end', r.right - 18),
      ('right grip', r.right - 3),
    ]) {
      await t.tapAt(Offset(x, r.center.dy));
      await t.pump();
      expect(details(key), findsOneWidget, reason: name);
      await tapBlank(t);
      expect(details(key), findsNothing, reason: 'closed after $name');
    }
  });

  testWidgets('a tap that wobbles 2 px still opens', (t) async {
    await pumpWork(t);
    final (key, r) = bars(t).first;
    final g = await t.startGesture(r.center);
    await g.moveBy(const Offset(2, 1));
    await g.up();
    await t.pump();
    expect(details(key), findsOneWidget);
  });

  testWidgets('another bar\'s tap switches the details over', (t) async {
    await pumpWork(t);
    final all = bars(t);
    final (a, ra) = all[0];
    await t.tapAt(ra.center);
    await t.pump();
    expect(details(a), findsOneWidget);
    // The panel took room: find the other bar again.
    final (b, rb) = bars(t).firstWhere((x) => x.$1 != a);
    await t.tapAt(rb.center);
    await t.pump();
    expect(details(b), findsOneWidget);
    expect(details(a), findsNothing);
  });

  testWidgets('a timeline bar\'s tap opens its row too', (t) async {
    await pumpWork(t, view: AppView.timeline);
    final bar = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('tl-bar-'),
        )
        .first;
    final key = (t.widget(bar).key! as ValueKey<String>).value.substring(
      'tl-bar-'.length,
    );
    final tap = find.descendant(
      of: bar,
      matching: find.byKey(const Key('bar-tap')),
    );
    await t.tapAt(t.getRect(tap).centerRight - const Offset(3, 0));
    await t.pump();
    expect(details(key), findsOneWidget);
  });
}
