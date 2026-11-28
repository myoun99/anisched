import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpShell(
  WidgetTester t, {
  CatalogueStore? existing,
}) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  Folds.cutsInDetails.value = true;
  addTearDown(() => Folds.cutsInDetails.value = false);
  final store = existing ?? sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return store;
}

PartGroup unit(CatalogueStore s, String key) =>
    s.partGroups(includeDone: true).firstWhere((g) => g.key == key);

/// Opens [g]'s line and its 「+」.
Future<void> openAdd(WidgetTester t, PartGroup g) async {
  await t.tap(find.byKey(Key('line-${g.key}')).first);
  await t.pump();
  final add = find.byKey(Key('cut-add-${g.key}'));
  await t.ensureVisible(add);
  await t.tap(add);
  await t.pumpAndSettle();
  expect(find.byKey(const Key('add-cuts')), findsOneWidget);
}

void main() {
  testWidgets('+ adds three cuts to a part, same stage and deadline', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    await openAdd(t, g);
    await t.enterText(find.byKey(const Key('add-count')), '3');
    await t.pump();
    await t.tap(find.byKey(const Key('add-ok')));
    await t.pump();
    await t.pump();
    final after = unit(store, g.key);
    expect(after.total, g.total + 3);
    final fresh = after.tasks.where((x) => !g.tasks.any((o) => o.id == x.id));
    expect(fresh, hasLength(3));
    for (final x in fresh) {
      expect(x.stageId, g.stageId);
      expect(x.partId, g.partId);
      expect(x.dueAt, g.dueAt);
    }
    expect(find.text('${g.total + 3} cut'), findsWidgets);
  });

  testWidgets('a number already in the episode blocks saving', (t) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    final taken = store.cuts(g.episodeId).first.number;
    final n = int.parse(RegExp(r'\d+').firstMatch(taken)![0]!);
    await openAdd(t, g);
    await t.enterText(find.byKey(const Key('add-start')), '$n');
    await t.pump();
    expect(find.byKey(const Key('add-clash')), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('add-ok'))).onPressed,
      isNull,
    );
  });

  testWidgets('loose cuts get their own task under the unit deadline', (
    t,
  ) async {
    final store = await pumpShell(t);
    // A loose cut (no part) with its own deadline.
    final p = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    final cut = store.addCut(p.episodeId, 'C900');
    store.addTask(
      p.stageId,
      cutId: cut,
      dueAt: now.add(const Duration(days: 5)),
    );
    await t.pumpWidget(const SizedBox());
    await pumpShell(t, existing: store);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.noPart);
    await openAdd(t, g);
    await t.tap(find.byKey(const Key('add-ok')));
    await t.pump();
    final after = unit(store, g.key);
    expect(after.total, g.total + 1);
    final fresh = after.tasks.firstWhere(
      (x) => !g.tasks.any((o) => o.id == x.id),
    );
    expect(fresh.stageId, g.stageId);
    expect(fresh.dueAt, g.dueAt);
  });
}
