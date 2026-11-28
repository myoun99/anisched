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

Future<CatalogueStore> pumpShell(WidgetTester t, {Size? size}) async {
  t.view.physicalSize = size ?? const Size(1280, 800);
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

/// A picked-task action, from the bar or from ⋯ when it did not fit.
Future<void> act(WidgetTester t, String key) async {
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    await t.tap(find.byKey(const Key('pick-more')));
    await t.pump();
  }
  await t.tap(find.byKey(Key(key)));
  await t.pump();
  await t.pump();
}

PartGroup openPart(CatalogueStore s) =>
    s.partGroups().firstWhere((g) => g.kind == GroupKind.part && g.inHand > 0);

Future<void> pick(WidgetTester t, PartGroup g) async {
  await t.longPress(find.byKey(Key('line-${g.key}')).first);
  await t.pump();
}

/// Turns 「보관한 것 보기」 in the filter on or off.
Future<void> toggleArchived(WidgetTester t) async {
  await t.tap(find.byKey(const Key('filter-button')));
  await t.pump();
  await t.tap(find.byKey(const Key('filter-archived')));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('archive: the card goes at once, the snack bar undoes it', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = openPart(store);
    await pick(t, g);
    await act(t, 'pick-archive');
    expect(store.partGroups().where((x) => x.key == g.key), isEmpty);
    expect(find.byKey(Key('line-${g.key}')), findsNothing);
    expect(
      store
          .partGroups(includeArchived: true)
          .firstWhere((x) => x.key == g.key)
          .archived,
      isTrue,
    );
    await t.pump(const Duration(milliseconds: 400)); // the bar slides in
    await t.tap(find.byKey(const Key('archived-undo')));
    await t.pump();
    await t.pump();
    expect(store.partGroups().where((x) => x.key == g.key), hasLength(1));
    expect(find.byKey(Key('line-${g.key}')), findsWidgets);
  });

  testWidgets('the filter shows archived cards; ⋯ brings them back', (t) async {
    final store = await pumpShell(t, size: const Size(390, 844));
    final g = openPart(store);
    store.archiveTasks([for (final x in g.tasks) x.id]);
    await t.pumpWidget(const SizedBox());
    await pumpShellWith(t, store);
    expect(find.byKey(Key('line-${g.key}')), findsNothing);
    await toggleArchived(t);
    final line = find.byKey(Key('line-${g.key}'));
    expect(line, findsWidgets);
    expect(
      find.ancestor(of: line.first, matching: find.byType(Opacity)),
      findsWidgets,
      reason: 'archived cards show faded',
    );
    await pick(t, g);
    await t.tap(find.byKey(const Key('pick-more')));
    await t.pump();
    expect(find.text('되돌리기'), findsOneWidget);
    expect(find.text('완전 삭제'), findsOneWidget);
    await t.tap(find.byKey(const Key('pick-archive')));
    await t.pump();
    await t.pump();
    expect(store.partGroups().where((x) => x.key == g.key), hasLength(1));
  });

  testWidgets('delete asks first: cancel keeps, confirm deletes', (t) async {
    final store = await pumpShell(t);
    final g = openPart(store);
    final cuts = {for (final x in g.tasks) x.cutId}.length;
    await pick(t, g);
    await act(t, 'pick-delete');
    expect(find.byKey(const Key('delete-confirm')), findsOneWidget);
    expect(find.textContaining('컷 $cuts'), findsOneWidget);
    expect(find.text('되돌릴 수 없습니다.'), findsOneWidget);
    await t.tap(find.byKey(const Key('delete-cancel')));
    await t.pump();
    expect(find.byKey(const Key('delete-confirm')), findsNothing);
    expect(store.partGroups().where((x) => x.key == g.key), hasLength(1));

    await act(t, 'pick-delete');
    await t.tap(find.byKey(const Key('delete-ok')));
    await t.pump();
    await t.pump();
    expect(
      store
          .partGroups(includeArchived: true, includeDone: true)
          .where((x) => x.key == g.key),
      isEmpty,
    );
    expect(find.byKey(Key('line-${g.key}')), findsNothing);
  });

  testWidgets('the confirmation counts the timer time that goes too', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = openPart(store);
    final ids = [for (final x in g.tasks) x.id];
    final sum = store.deletionSummary(ids);
    await pick(t, g);
    await act(t, 'pick-delete');
    expect(
      find.byKey(const Key('delete-time')),
      sum.timerMinutes > 0 ? findsOneWidget : findsNothing,
    );
  });
  // The user-visible failure: the same cut × stage is in work again, so
  // bringing the archived task back is refused with a note.
  testWidgets('unarchiving over a live task says why and restores nothing', (
    t,
  ) async {
    Folds.cutsInDetails.value = true;
    addTearDown(() => Folds.cutsInDetails.value = false);
    final store = sampleCatalogue(now);
    final g = openPart(store);
    final old = g.tasks.first;
    store.archiveTasks([old.id]);
    // Registered again: a live task on the same cut × stage.
    expect(store.addTasksForPart(g.partId!, g.stageId), hasLength(1));
    await pumpShellWith(t, store, size: const Size(1280, 800));
    await toggleArchived(t);
    await t.tap(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
    final chip = find.byKey(Key('cut-${old.id}'));
    await t.ensureVisible(chip);
    await t.longPress(chip);
    await t.pump();
    await act(t, 'pick-archive');
    expect(find.byKey(const Key('restore-blocked')), findsOneWidget);
    expect(find.textContaining('되돌릴 수 없음'), findsOneWidget);
    final row = store
        .partGroups(includeArchived: true)
        .expand((x) => x.tasks)
        .firstWhere((x) => x.id == old.id);
    expect(row.archived, isTrue, reason: 'nothing came back');
  });
}

Future<void> pumpShellWith(
  WidgetTester t,
  CatalogueStore store, {
  Size? size,
}) async {
  if (size != null) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }
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
}
