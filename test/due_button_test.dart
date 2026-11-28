import 'package:anisched/src/models/progress.dart';
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

  testWidgets('the details 마감 sets the deadline', (t) async {
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
  });

  testWidgets('a long press on a cut picks it for the bar', (t) async {
    final store = await pumpShell(t, AppView.list);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    final task = g.tasks.first;
    await t.longPress(find.byKey(Key('cut-${task.id}')));
    await t.pump();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('1건'), findsWidgets);
    final fill = t.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(Key('cut-${task.id}')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final theme = Theme.of(t.element(find.byKey(Key('cut-${task.id}'))));
    expect(
      (fill.decoration as BoxDecoration).color,
      theme.extension<AppColors>()!.selected,
      reason: 'the picked cut shows it',
    );
  });

  testWidgets('the timeline D label sets the deadline too', (t) async {
    final store = await pumpShell(t, AppView.timeline);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    await t.tap(find.byKey(Key('tl-due-${g.key}')));
    await t.pump();
    await pickDay(t, '30');
    final due = store.partGroups().firstWhere((x) => x.key == g.key).dueAt!;
    // A picked day is due at its end, so the day itself is never late.
    expect(
      (due.toLocal().day, due.toLocal().hour, due.toLocal().minute),
      (30, 23, 59),
    );
  });

  testWidgets('only the D label opens the picker, not the space beside it', (
    t,
  ) async {
    final store = await pumpShell(t, AppView.list);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    final d = t.getRect(find.byKey(Key('due-${g.key}')));
    await t.tapAt(Offset(d.left - 12, d.center.dy));
    await t.pump();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byKey(Key('details-${g.key}')), findsOneWidget);
  });

  testWidgets('the details dates each open a titled picker and save', (
    t,
  ) async {
    final store = await pumpShell(t, AppView.list);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    PartGroup latest() => store.partGroups().firstWhere((x) => x.key == g.key);
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();

    await t.tap(find.byKey(Key('details-kickoff-${g.key}')));
    await t.pump();
    expect(find.text('착수일'), findsOneWidget);
    await pickDay(t, '20');
    expect(latest().kickoffAt!.toLocal().day, 20);

    await t.tap(find.byKey(Key('details-plan-end-${g.key}')));
    await t.pump();
    expect(find.text('작업 끝'), findsOneWidget);
    await pickDay(t, '29');
    expect(latest().planEndAt!.toLocal().day, 29);

    await t.tap(find.byKey(Key('details-plan-start-${g.key}')));
    await t.pump();
    expect(find.text('작업 시작'), findsOneWidget);
    await pickDay(t, '28');
    expect(latest().planStartAt!.toLocal().day, 28);
    expect(latest().planEndAt!.toLocal().day, 29, reason: 'the end stays');
  });

  testWidgets('picked cuts get their own deadline from the bar', (t) async {
    final store = await pumpShell(t, AppView.list);
    final g = store.partGroups().firstWhere((g) => g.partId != null);
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    final task = g.tasks.first;
    await t.longPress(find.byKey(Key('cut-${task.id}')));
    await t.pump();
    await t.tap(find.byKey(const Key('pick-due')));
    await t.pump();
    expect(find.text('마감 날짜'), findsOneWidget);
    await pickDay(t, '26');
    final row = store.partGroups().expand((x) => x.tasks).firstWhere(
      (x) => x.id == task.id,
    );
    expect(row.ownDueAt!.toLocal().day, 26);
    expect(row.dueAt!.toLocal().day, 26, reason: 'over the part');
  });
}
