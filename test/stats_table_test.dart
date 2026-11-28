import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/stats_tree.dart';
import 'package:anisched/src/ui/views/stats_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

/// The stats tab at [width], turned to its table.
Future<CatalogueStore> pumpTable(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(() => statsAsTable.value = false);
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
  await t.tap(find.byKey(const Key('stats-table')));
  await t.pump();
  await t.pump();
  return store;
}

String keyOf(StatsNode n) => '${n.kind.name}:${n.id}';

Future<void> open(WidgetTester t, StatsNode n) async {
  final row = find.byKey(Key('stats-row-${keyOf(n)}'));
  await t.ensureVisible(row);
  await t.tap(row);
  await t.pump();
}

/// The store's own tree, as the table shows it (3 months to now).
StatsNode treeOf(CatalogueStore s) =>
    s.statsTree(from: DateTime(2026, 8, 27), to: now);

void main() {
  testWidgets('the toolbar turns summary into the table and back', (t) async {
    await pumpTable(t, 1280);
    expect(find.byType(StatsTreeTable), findsOneWidget);
    await t.tap(find.byKey(const Key('stats-table')));
    await t.pump();
    expect(find.byType(StatsTreeTable), findsNothing);
  });

  testWidgets('rows open from a client down to a cut and its stages', (
    t,
  ) async {
    final store = await pumpTable(t, 1280);
    var n = treeOf(store);
    while (n.children.isNotEmpty) {
      n = n.children.first;
      expect(find.byKey(Key('stats-row-${keyOf(n)}')), findsOneWidget);
      await open(t, n);
    }
    expect(n.kind, StatsNodeKind.cut);
    expect(find.byKey(Key('stats-open-${keyOf(n)}')), findsOneWidget);
    for (final stage in n.stages.keys) {
      expect(find.byKey(Key('stats-stage-$stage')), findsOneWidget);
    }
  });

  testWidgets('a column head sorts a level by it, then turns', (t) async {
    final store = await pumpTable(t, 1280);
    final clients = treeOf(store).children;
    expect(clients.length, greaterThan(1));
    double top(StatsNode n) =>
        t.getTopLeft(find.byKey(Key('stats-row-${keyOf(n)}'))).dy;
    final byCuts = [...clients]..sort((a, b) => b.cuts.compareTo(a.cuts));
    await t.tap(find.byKey(const Key('stats-sort-cuts')));
    await t.pump();
    expect(top(byCuts.first), lessThan(top(byCuts.last)));
    await t.tap(find.byKey(const Key('stats-sort-cuts')));
    await t.pump();
    expect(top(byCuts.last), lessThan(top(byCuts.first)));
  });

  testWidgets('a narrow screen shows two columns; an opened row the rest', (
    t,
  ) async {
    final store = await pumpTable(t, 390);
    expect(find.byKey(const Key('stats-sort-cuts')), findsOneWidget);
    expect(find.byKey(const Key('stats-sort-worked')), findsOneWidget);
    expect(find.byKey(const Key('stats-sort-pay')), findsNothing);
    final first = treeOf(store).children.first;
    await open(t, first);
    final line = find.byKey(Key('stats-open-${keyOf(first)}'));
    expect(line, findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.textContaining('금액')),
      findsOneWidget,
    );
  });
}
