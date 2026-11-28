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

// A saved cut's own tools (were the register screen's grid) live on the
// cards now: pick cut chips, then the selection bar.
Future<CatalogueStore> pumpShell(WidgetTester t) async {
  t.view.physicalSize = const Size(1920, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  Folds.cutsInDetails.value = true;
  addTearDown(() => Folds.cutsInDetails.value = false);
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

PartGroup part(CatalogueStore s) => s.partGroups().firstWhere(
  (g) => g.kind == GroupKind.part && g.tasks.length >= 3,
);

/// Opens [g]'s line and long-presses its cut chips [tasks].
Future<void> pickCuts(WidgetTester t, PartGroup g, List<TaskRow> tasks) async {
  if (find.byKey(Key('cut-${tasks.first.id}')).evaluate().isEmpty) {
    await t.tap(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
  }
  for (final x in tasks) {
    final chip = find.byKey(Key('cut-${x.id}'));
    await t.ensureVisible(chip);
    await t.longPress(chip);
    await t.pump();
  }
}

Future<void> act(WidgetTester t, String key) async {
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    await t.tap(find.byKey(const Key('pick-more')));
    await t.pump();
  }
  await t.tap(find.byKey(Key(key)));
  await t.pump();
  await t.pump();
}

VoidCallback? onTapOf(WidgetTester t, String key) => t
    .widget<InkWell>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)),
    )
    .onTap;

void main() {
  testWidgets('two picked cuts join as shared, and come apart', (t) async {
    final store = await pumpShell(t);
    final g = part(store);
    final [a, b, ...] = g.tasks;
    await pickCuts(t, g, [a, b]);
    await act(t, 'pick-share');
    bool shared(int cut) =>
        store.cuts(g.episodeId).firstWhere((c) => c.id == cut).sharedLabel !=
        null;
    expect(shared(a.cutId!), isTrue);
    expect(find.byKey(Key('cut-${b.id}')), findsNothing, reason: 'one chip');

    // The shared chip picked: the same button takes the group apart.
    await pickCuts(t, g, [a]);
    expect(find.text('겸용 풀기'), findsOneWidget);
    await act(t, 'pick-share');
    expect(shared(a.cutId!), isFalse);
  });

  testWidgets('cuts of two episodes cannot be shared', (t) async {
    final store = await pumpShell(t);
    final groups = store.partGroups().where((g) => g.kind == GroupKind.part);
    final g1 = groups.first;
    final g2 = groups.firstWhere((g) => g.episodeId != g1.episodeId);
    // Both lines open first (a tap while picking picks the line).
    for (final g in [g1, g2]) {
      await t.tap(find.byKey(Key('line-${g.key}')).first);
      await t.pump();
    }
    await pickCuts(t, g1, [g1.tasks.first]);
    await pickCuts(t, g2, [g2.tasks.first]);
    expect(find.byKey(const Key('picked-count')), findsOneWidget);
    expect(onTapOf(t, 'pick-share'), isNull);
  });

  testWidgets('a cut taken out goes from the card; undo puts it back', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = part(store);
    final x = g.tasks.first;
    await pickCuts(t, g, [x]);
    await act(t, 'pick-takeout');
    List<int> live() => [for (final c in store.cuts(g.episodeId)) c.id];
    expect(live(), isNot(contains(x.cutId)));
    expect(find.byKey(Key('cut-${x.id}')), findsNothing);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('takeout-undo')));
    await t.pump();
    await t.pump();
    expect(live(), contains(x.cutId));
  });

  testWidgets('one picked cut is renamed', (t) async {
    final store = await pumpShell(t);
    final g = part(store);
    final x = g.tasks.first;
    await pickCuts(t, g, [x]);
    await act(t, 'pick-rename');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name-input')), '${x.cutNumber}X');
    await t.tap(find.byKey(const Key('name-ok')));
    await t.pumpAndSettle();
    expect(
      store.cuts(g.episodeId).map((c) => c.number),
      contains('${x.cutNumber}X'),
    );
  });
}
