import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpRegister(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: AppShell(
        initialView: AppView.register,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return store;
}

void main() {
  for (final size in const [
    Size(1440, 900),
    Size(800, 1280),
    Size(412, 915),
    Size(915, 412),
  ]) {
    testWidgets('register lays out at $size', (t) async {
      await pumpRegister(t, size);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('role-원화')), findsOneWidget);
      if (size.height > 600) {
        expect(find.byKey(const Key('cell-C001')), findsOneWidget);
      }
    });
  }

  testWidgets('a role checks its stages; a stage box toggles alone', (t) async {
    await pumpRegister(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('role-작감')));
    await t.pump();
    final lo = find.descendant(
      of: find.byKey(const Key('stage-LO 작감 수정')),
      matching: find.byType(Checkbox),
    );
    expect(t.widget<Checkbox>(lo).value, isTrue);
    await t.tap(find.byKey(const Key('stage-LO 작감 수정')));
    await t.pump();
    expect(t.widget<Checkbox>(lo).value, isFalse);
  });

  testWidgets('drag-pick cells, take them out, register a new work', (t) async {
    final store = await pumpRegister(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('flow-newWork')));
    await t.pump();
    await t.enterText(find.byKey(const Key('reg-title')), '새벽의 정원');
    await t.enterText(find.byKey(const Key('reg-count')), '10');
    await t.pump();
    expect(find.byKey(const Key('cell-C011')), findsNothing);

    final g = await t.startGesture(
      t.getCenter(find.byKey(const Key('cell-C002'))),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveTo(t.getCenter(find.byKey(const Key('cell-C003'))));
    await g.moveTo(t.getCenter(find.byKey(const Key('cell-C004'))));
    await g.up();
    await t.pump();
    await t.tap(find.byKey(const Key('cut-remove')));
    await t.pump();
    expect(find.text('7 cut'), findsOneWidget);

    await t.tap(find.byKey(const Key('register')));
    await t.pump();
    await t.pump();
    final work = store.works().firstWhere((w) => w.title == '새벽의 정원');
    final groups = store.partGroups(workId: work.id);
    expect(groups.map((g) => g.stageName).toSet(), {'LO', '원화'});
    expect(groups.every((g) => g.total == 7), isTrue);
  });
}
