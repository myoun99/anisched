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
  for (final l
      in s.cardEvents(from: DateTime(2026, 10), to: DateTime(2027)).values)
    ...l,
];

/// A chart bar's whole date area (its [ChartBar]).
Finder chartOf(Finder tap) =>
    find.ancestor(of: tap, matching: find.byType(ChartBar)).first;

/// The first timeline bar with room: its drawn face (`bar-tap`), its
/// window, a day's width and the face's left edge.
(Finder, ChartWindow, double, double) firstBar(WidgetTester t) {
  final taps = find.byKey(const Key('bar-tap'));
  for (var i = 0; i < taps.evaluate().length; i++) {
    final bar = taps.at(i);
    final chart = t.widget<ChartBar>(chartOf(bar));
    final dw = t.getRect(chartOf(bar)).width / chart.window.days;
    final r = t.getRect(bar);
    if (r.width >= dw * 3 && r.left > 300) {
      return (bar, chart.window, dw, r.left);
    }
  }
  throw StateError('no bar three days long');
}

void main() {
  testWidgets('a long press on a row off its bar does nothing', (t) async {
    final store = await pumpTimeline(t);
    final before = allEvents(store).length;
    final (bar, _, dw, _) = firstBar(t);
    final r = t.getRect(bar);
    final row = t.getRect(chartOf(bar));
    // Past the bar's end, in the same row.
    final x = r.right + dw * 1.5 < row.right
        ? r.right + dw * 1.5
        : row.left + 5;
    await t.longPressAt(Offset(x, r.center.dy));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('event-title')), findsNothing);
    expect(allEvents(store), hasLength(before));
  });

  testWidgets('a long press on a bar adds an event; its mark edits it', (
    t,
  ) async {
    final store = await pumpTimeline(t);
    final before = allEvents(store).length;
    // A bar's 2nd day (no event there yet).
    final (bar, window, dw, x) = firstBar(t);
    await t.longPressAt(Offset(x + dw * 1.5, t.getRect(bar).center.dy));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('event-title')), 'テスト収録');
    await t.enterText(find.byKey(const Key('event-note')), '스튜디오 B');
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();

    expect(allEvents(store), hasLength(before + 1));
    final added = allEvents(store).singleWhere((e) => e.title == 'テスト収録');
    expect(added.note, '스튜디오 B');
    expect(added.timeMinutes, isNull);
    final day = window.dayAt(
      ((x + dw * 1.5 - t.getRect(chartOf(bar)).left) / dw).floor(),
    );
    expect((added.date.month, added.date.day), (day.month, day.day));
    // That card's alone: on its bar, not the episode's other rows.
    final card = (t.widget(chartOf(bar)).key! as ValueKey<String>).value
        .substring('tl-bar-'.length);
    expect(added.card, card);
    Finder mark(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(EventMark));
    expect(mark('テスト収録'), findsOneWidget);

    // The mark opens the same window: rename, then remove.
    await t.tap(mark('テスト収録').first);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('event-title')), '再収録');
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();
    expect(allEvents(store).singleWhere((e) => e.id == added.id).title, '再収録');
    await t.tap(mark('再収録').first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('event-delete')));
    await t.pumpAndSettle();
    expect(allEvents(store), hasLength(before));
    expect(mark('再収録'), findsNothing);
  });

  testWidgets('an empty title saves nothing', (t) async {
    final store = await pumpTimeline(t);
    final before = allEvents(store).length;
    final (bar, _, _, _) = firstBar(t);
    await t.longPress(bar);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('event-title')), findsOneWidget);
    expect(allEvents(store), hasLength(before));
  });

  testWidgets('an event on a bar\'s day sits inside it; others do not', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    chartView.value = const ChartView();
    final store = sampleCatalogue(now);
    // A unit with a bar: one event inside its days, one a week past.
    final g = store.partGroups().firstWhere(
      (g) => g.kickoffAt != null && g.dueAt != null && g.dueAt!.isAfter(now),
    );
    final inside = store.addEvent(
      episodeId: g.episodeId,
      date: g.dueAt!,
      title: '안',
    );
    final outside = store.addEvent(
      episodeId: g.episodeId,
      date: g.dueAt!.add(const Duration(days: 7)),
      title: '밖',
    );
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
    // The marks on this unit's own row.
    EventMark markOf(int id) => t.widget<EventMark>(
      find.descendant(
        of: find.byKey(Key('tl-event-${g.key}-$id')),
        matching: find.byType(EventMark),
      ),
    );
    expect(markOf(inside).onBar, isTrue);
    expect(markOf(outside).onBar, isFalse);
  });
}
