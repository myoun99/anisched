import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/views/stats_view.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/stats_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

/// A small tree: one client, two works, the first with an episode, a
/// unit and two cuts.
List<StatsNode> tree() => [
  StatsNode(
    key: 'client:1',
    level: StatsLevel.client,
    label: '스튜디오 하늘',
    clientColor: const Color(0xFF4A7BE0),
    cuts: 6,
    worked: const Duration(hours: 5),
    pay: 30000,
    children: [
      StatsNode(
        key: 'work:1',
        level: StatsLevel.work,
        label: '별빛 정류장',
        cuts: 2,
        worked: const Duration(hours: 1),
        pay: 9000,
        children: [
          StatsNode(
            key: 'episode:1',
            level: StatsLevel.episode,
            label: '#07',
            cuts: 2,
            worked: const Duration(hours: 1),
            pay: 9000,
            children: [
              StatsNode(
                key: 'unit:1',
                level: StatsLevel.unit,
                label: 'A파트 원화',
                stageName: '원화',
                cuts: 2,
                worked: const Duration(hours: 1),
                pay: 9000,
                children: [
                  for (final (n, m) in [(12, 40), (14, 20)])
                    StatsNode(
                      key: 'cut:$n',
                      level: StatsLevel.cut,
                      label: 'C0$n',
                      cuts: 1,
                      worked: Duration(minutes: m),
                      pay: 4500,
                      workedByStage: {'원화': Duration(minutes: m)},
                      intervals: 3,
                      retakeRound: 2,
                      status: TaskStatus.submitted,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
      const StatsNode(
        key: 'work:2',
        level: StatsLevel.work,
        label: '마법소녀 리코',
        cuts: 4,
        worked: Duration(hours: 4),
        pay: 21000,
      ),
    ],
  ),
];

Future<void> pump(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: StatsTreeTable(roots: tree())),
    ),
  );
}

Future<void> open(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key('stats-row-$key')));
  await t.pump();
}

double top(WidgetTester t, String key) =>
    t.getTopLeft(find.byKey(Key('stats-row-$key'))).dy;

void main() {
  testWidgets('rows open down to the cuts', (t) async {
    await pump(t, 1280);
    expect(find.byKey(const Key('stats-row-work:1')), findsNothing);
    for (final k in ['client:1', 'work:1', 'episode:1', 'unit:1']) {
      await open(t, k);
    }
    expect(find.byKey(const Key('stats-row-cut:12')), findsOneWidget);
    // A cut opened: its time per stage, timer runs, take.
    await open(t, 'cut:12');
    expect(find.byKey(const Key('stats-open-cut:12')), findsOneWidget);
    expect(find.byKey(const Key('stats-stage-원화')), findsOneWidget);
  });

  testWidgets('a column head sorts each level by it, then turns', (t) async {
    await pump(t, 1280);
    await open(t, 'client:1');
    // By time, most first: 마법소녀 (4h) over 별빛 (1h).
    await t.tap(find.byKey(const Key('stats-sort-worked')));
    await t.pump();
    expect(top(t, 'work:2'), lessThan(top(t, 'work:1')));
    await t.tap(find.byKey(const Key('stats-sort-worked')));
    await t.pump();
    expect(top(t, 'work:1'), lessThan(top(t, 'work:2')));
  });

  testWidgets('a narrow screen shows two columns; an opened row the rest', (
    t,
  ) async {
    await pump(t, 390);
    expect(find.byKey(const Key('stats-sort-cuts')), findsOneWidget);
    expect(find.byKey(const Key('stats-sort-worked')), findsOneWidget);
    expect(find.byKey(const Key('stats-sort-pay')), findsNothing);
    await open(t, 'client:1');
    expect(find.byKey(const Key('stats-open-client:1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-open-client:1')),
        matching: find.textContaining('30,000'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the stats toolbar turns summary into the table and back', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() => statsAsTable.value = false);
    final now = DateTime(2026, 11, 27, 14);
    final store = sampleCatalogue(now);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.stats,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    expect(find.byType(StatsTreeTable), findsNothing);
    await t.tap(find.byKey(const Key('stats-table')));
    await t.pump();
    expect(find.byType(StatsTreeTable), findsOneWidget);
    await t.tap(find.byKey(const Key('stats-table')));
    await t.pump();
    expect(find.byType(StatsTreeTable), findsNothing);
  });
}
