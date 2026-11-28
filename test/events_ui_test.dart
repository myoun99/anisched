import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:anisched/src/ui/views/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpTimeline(WidgetTester t) async {
  t.view.physicalSize = const Size(1280, 800);
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
  return store;
}

List<EventRow> allEvents(CatalogueStore s) => [
  for (final l in s.events(from: DateTime(2026, 10), to: DateTime(2027)).values)
    ...l,
];

void main() {
  testWidgets('a long press on a day adds an event; its mark edits it', (
    t,
  ) async {
    final store = await pumpTimeline(t);
    // The first row's days; its 3rd day from the left.
    final press = find.byType(ChartDayPress).first;
    final box = t.getRect(press);
    final window = t.widget<ChartDayPress>(press).window;
    final dw = box.width / window.days;
    await t.longPressAt(Offset(box.left + dw * 2.5, box.center.dy));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('event-title')), 'アフレコ');
    await t.enterText(find.byKey(const Key('event-note')), '스튜디오 B');
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();

    final added = allEvents(store);
    expect(added, hasLength(1));
    expect(added.single.title, 'アフレコ');
    expect(added.single.note, '스튜디오 B');
    expect(added.single.timeMinutes, isNull);
    final day = window.dayAt(2);
    expect(
      (added.single.date.month, added.single.date.day),
      (day.month, day.day),
    );
    // Shown on the rows of that episode.
    expect(find.byType(EventMark), findsWidgets);

    // The mark opens the same window: rename, then remove.
    await t.tap(find.byType(EventMark).first);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('event-title')), '打ち合わせ');
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();
    expect(allEvents(store).single.title, '打ち合わせ');
    await t.tap(find.byType(EventMark).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('event-delete')));
    await t.pumpAndSettle();
    expect(allEvents(store), isEmpty);
    expect(find.byType(EventMark), findsNothing);
  });

  testWidgets('an empty title saves nothing', (t) async {
    final store = await pumpTimeline(t);
    final press = find.byType(ChartDayPress).first;
    await t.longPress(press);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('event-title')), findsOneWidget);
    expect(allEvents(store), isEmpty);
  });
}
