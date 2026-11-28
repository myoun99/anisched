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
    expect(after.partWaiting, isTrue, reason: 'a whole part waits as a part');
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
    await pumpShell(t, size: const Size(390, 844));
    await t.tap(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
