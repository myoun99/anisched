import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpShell(WidgetTester t) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
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

int clientIdOf(CatalogueStore s, String name) =>
    s.clients().firstWhere((c) => c.name == name).id;

void main() {
  testWidgets('edit: a new client shows on the card and in the filter', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.part && g.clientName == '스튜디오 하늘',
    );
    final line = find.byKey(Key('line-${g.key}'));
    await t.longPress(line.first);
    await t.pump();
    await t.tap(find.byKey(const Key('pick-edit')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('bundle-editor')), findsOneWidget);
    await t.tap(find.byKey(const Key('pick-client')));
    await t.pumpAndSettle();
    await t.tap(find.text('애니웍스').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('edit-subtitle')), '星の駅');
    await t.tap(find.byKey(const Key('edit-ok')));
    await t.pump();
    await t.pump();

    final work = store.works().firstWhere((w) => w.id == g.workId);
    expect(work.clientId, clientIdOf(store, '애니웍스'));
    expect(
      store.episodes(g.workId).firstWhere((e) => e.id == g.episodeId).title,
      '星の駅',
    );
    // The card's chip, and the filter by the new client keeps it.
    expect(
      find.descendant(of: line.first, matching: find.text('애니웍스')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('filter-button')));
    await t.pump();
    await t.tap(find.text('애니웍스').last);
    await t.pump();
    await t.pump();
    expect(line, findsWidgets);
  });

  testWidgets('edit renames the part and the work', (t) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    await t.longPress(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
    await t.tap(find.byKey(const Key('pick-edit')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('edit-work')), '새 제목');
    await t.enterText(find.byKey(const Key('edit-part')), 'Z');
    await t.tap(find.byKey(const Key('edit-ok')));
    await t.pump();
    final after = store.partGroups().firstWhere(
      (x) => x.partId == g.partId && x.stageId == g.stageId,
    );
    expect(after.workTitle, '새 제목');
    expect(after.partLabel, 'Z');
  });

  testWidgets('picking more than one bundle greys edit out', (t) async {
    final store = await pumpShell(t);
    final parts = store.partGroups().where((g) => g.kind == GroupKind.part);
    final a = parts.first;
    final b = parts.firstWhere((g) => g.partId != a.partId);
    await t.longPress(find.byKey(Key('line-${a.key}')).first);
    await t.pump();
    InkWell edit() => t.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('pick-edit')),
        matching: find.byType(InkWell),
      ),
    );
    expect(edit().onTap, isNotNull);
    await t.longPress(find.byKey(Key('line-${b.key}')).first);
    await t.pump();
    expect(edit().onTap, isNull);
  });
}
