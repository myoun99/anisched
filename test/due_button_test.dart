import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpShell(WidgetTester t, AppView view) async {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: view,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return store;
}

Future<void> pickDay(WidgetTester t, String day) async {
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await t.tap(find.text(day).last);
  await t.pump();
  await t.tap(find.text('OK'));
  await t.pump();
  await t.pump();
}

void main() {
  setUp(() {
    Folds.cutsInDetails.value = true;
    Folds.newCuts.value = true;
    Folds.savedCuts.value = true;
  });

  // The list D label: hold_rounds_test (it adds a round).

  testWidgets('the details 마감 and a cut chip long press', (t) async {
    final store = await pumpShell(t, AppView.list);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    await t.tap(find.byKey(Key('details-due-${g.key}')));
    await t.pump();
    await pickDay(t, '28');
    expect(
      store.partGroups().firstWhere((x) => x.key == g.key).dueAt!.toLocal().day,
      28,
    );
    final task = g.tasks.first;
    await t.longPress(find.byKey(Key('cut-${task.id}')));
    await t.pump();
    await pickDay(t, '26');
    final row = store
        .partGroups()
        .expand((x) => x.tasks)
        .firstWhere((x) => x.id == task.id);
    expect(row.ownDueAt!.toLocal().day, 26);
  });

  testWidgets('the timeline D label sets the deadline too', (t) async {
    final store = await pumpShell(t, AppView.timeline);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    await t.tap(find.byKey(Key('tl-due-${g.key}')));
    await t.pump();
    await pickDay(t, '30');
    expect(
      store.partGroups().firstWhere((x) => x.key == g.key).dueAt!.toLocal().day,
      30,
    );
  });
}
