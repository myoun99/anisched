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
  Size? size,
  CatalogueStore? existing,
}) async {
  t.view.physicalSize = size ?? const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
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

PartGroup partOf(CatalogueStore s, String key) =>
    s.partGroups().firstWhere((g) => g.key == key);

Future<void> pickDay(WidgetTester t, String day) async {
  await t.tap(find.text(day).last);
  await t.pump();
  await t.tap(find.text('OK'));
  await t.pump();
  await t.pump();
}

void main() {
  setUp(() {
    Folds.cutsInDetails.value = true;
    Folds.dueRounds.value = false;
  });

  testWidgets('picked lines go on hold with a reason, then come off', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.part && g.inHand > 0,
    );
    await t.longPress(find.byKey(Key('line-${g.key}')));
    await t.pump();
    await t.tap(find.byKey(const Key('pick-hold')));
    await t.pump();
    await t.enterText(find.byKey(const Key('hold-reason')), 'LO 待ち');
    await t.tap(find.byKey(const Key('hold-ok')));
    await t.pump();
    await t.pump();
    var after = partOf(store, g.key);
    expect(after.inHand, 0);
    expect(after.tasks.first.waitReason, 'LO 待ち');
    expect(find.byKey(Key('hold-mark-${g.key}')), findsOneWidget);

    await t.longPress(find.byKey(Key('line-${g.key}')));
    await t.pump();
    expect(find.text('대기 해제'), findsOneWidget);
    await t.tap(find.byKey(const Key('pick-hold')));
    await t.pump();
    await t.pump();
    after = partOf(store, g.key);
    expect(after.waiting, 0);
    expect(after.inHand, g.inHand);
  });

  testWidgets('the details show 보유 · 대기 and hold the unit', (t) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.part && g.inHand > 0,
    );
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    expect(find.textContaining('보유 ${g.inHand}'), findsOneWidget);
    await t.tap(find.byKey(Key('hold-${g.key}')));
    await t.pump();
    await t.tap(find.byKey(const Key('hold-ok')));
    await t.pump();
    await t.pump();
    expect(partOf(store, g.key).inHand, 0);
    expect(find.textContaining('대기 ${g.inHand}'), findsOneWidget);
  });

  testWidgets('a new deadline is a new round; a round can be corrected', (
    t,
  ) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.part && g.dueAt != null,
    );
    final before = g.dueRevision;
    await t.tap(find.byKey(Key('due-${g.key}')));
    await t.pump();
    await pickDay(t, '30');
    var after = partOf(store, g.key);
    expect(after.dueRevision, before + 1);
    expect(after.dueAt!.toLocal().day, 30);

    // The badge shows the round; the list under the details corrects one.
    expect(find.text('${before + 1}'), findsWidgets);
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    await t.tap(find.byKey(Key('fold-rounds-${g.key}')));
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(Key('due-round-${before + 1}')));
    await t.pump();
    await pickDay(t, '29');
    after = partOf(store, g.key);
    expect(after.dueRevision, before + 1, reason: 'a correction, not a round');
    expect(after.dueAt!.toLocal().day, 29);
  });

  testWidgets('holds and rounds lay out on a small phone', (t) async {
    final store = await pumpShell(t, size: const Size(390, 844));
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    store.extendDue(
      DueTarget.part(g.partId!, g.stageId),
      now.add(const Duration(days: 9)),
    );
    store.setPartWaiting(g.partId!, g.stageId, waiting: true, reason: '素材待ち');
    await t.pumpWidget(const SizedBox());
    await pumpShell(t, size: const Size(390, 844), existing: store);
    await t.tap(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('picked cuts are pulled at once, with an undo', (t) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.part && g.inHand > 0,
    );
    await t.longPress(find.byKey(Key('line-${g.key}')));
    await t.pump();
    // Pull waits behind ⋯ when the bar is short of room.
    if (find.byKey(const Key('pick-drop')).evaluate().isEmpty) {
      await t.tap(find.byKey(const Key('pick-more')));
      await t.pump();
    }
    await t.tap(find.byKey(const Key('pick-drop')));
    await t.pump();
    await t.pump();
    expect(store.partGroups().where((x) => x.key == g.key), isEmpty);
    expect(
      store
          .partGroups(includeHandedOff: true)
          .firstWhere((x) => x.key == g.key)
          .tasks
          .every((x) => x.handedOff),
      isTrue,
    );
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('dropped-undo')));
    await t.pump();
    await t.pump();
    expect(store.partGroups().where((x) => x.key == g.key), hasLength(1));
  });

  testWidgets('the filter can show pulled work again', (t) async {
    final store = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    store.handOffPart(g.partId!, g.stageId);
    await t.pumpWidget(const SizedBox());
    await pumpShell(t, existing: store);
    expect(find.byKey(Key('line-${g.key}')), findsNothing);
    await t.tap(find.byKey(const Key('filter-button')));
    await t.pump();
    await t.tap(find.text('빠진 것도 보기'));
    await t.pump();
    await t.pump();
    expect(find.byKey(Key('line-${g.key}')), findsOneWidget);
  });

  testWidgets('a tap on a timeline row opens the list details below it', (
    t,
  ) async {
    final store = await pumpShell(t);
    await t.tap(find.byKey(const Key('view-tab-timeline')));
    await t.pump();
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    await t.tap(find.byKey(Key('tl-label-${g.key}')));
    await t.pump();
    final details = find.byKey(Key('details-${g.key}'));
    expect(details, findsOneWidget);
    // Across the whole board, label column and dates.
    expect(t.getRect(details).width, greaterThan(1280 * 0.9));
    await t.tap(find.byKey(Key('details-kickoff-${g.key}')));
    await t.pump();
    expect(find.text('착수일'), findsOneWidget, reason: 'the same details');
  });
}
