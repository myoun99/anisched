import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

void main() {
  setUp(() {
    Folds.cutsInDetails.value = true;
    Folds.newCuts.value = true;
    Folds.savedCuts.value = true;
  });

  testWidgets('a picked cut waits paused; the toggle records and the total '
      'keeps adding up', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var now = DateTime(2026, 11, 27, 14);
    final store = sampleCatalogue(now);
    final timer = WorkTimerStore(store.db, clock: () => now);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          reader: SyncCatalogueReader(store),
          store: store,
          timer: timer,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    final g = store.partGroups().first;
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    final task = g.tasks.first;
    await t.tap(find.byKey(Key('cut-${task.id}')));
    await t.pump();
    expect(timer.running(), isNull, reason: 'picking does not start');
    expect(find.text('00:00:00'), findsOneWidget);

    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    expect(timer.running()?.taskId, task.id);
    now = now.add(const Duration(minutes: 5));
    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    expect(timer.running(), isNull);
    expect(find.text('00:05:00'), findsOneWidget, reason: 'paused keeps total');

    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    now = now.add(const Duration(minutes: 2));
    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    expect(find.text('00:07:00'), findsOneWidget);
  });

  group('the bar', () {
    Future<(CatalogueStore, WorkTimerStore, int)> pick(WidgetTester t) async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final now = DateTime(2026, 11, 27, 14);
      final store = sampleCatalogue(now);
      final timer = WorkTimerStore(store.db, clock: () => now);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            reader: SyncCatalogueReader(store),
            store: store,
            timer: timer,
            clock: () => now,
          ),
        ),
      );
      await t.pump();
      final g = store.partGroups().firstWhere((g) => g.tasks.length > 2);
      await t.tap(find.byKey(Key('line-${g.key}')));
      await t.pump();
      final task = g.tasks.first;
      await t.tap(find.byKey(Key('cut-${task.id}')));
      await t.pump();
      return (store, timer, task.id);
    }

    testWidgets('the cut name opens its episode with this cut in the middle', (
      t,
    ) async {
      final (store, _, id) = await pick(t);
      await t.tap(find.byKey(const Key('timer-cut')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('pick-current')), findsOneWidget);
      // The next row is the next cut: one tap moves the bar on.
      final now = t.getRect(find.byKey(const Key('pick-current')));
      final below = find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.key != const Key('pick-current') &&
            w.key is ValueKey<String>,
      );
      final next = below
          .evaluate()
          .map((e) => t.getRect(find.byWidget(e.widget)))
          .firstWhere((r) => r.top >= now.bottom - 1);
      await t.tapAt(next.center);
      await t.pump();
      expect(find.byKey(const Key('timer-cut')), findsOneWidget);
      final shown = t.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('timer-cut')),
          matching: find.byType(Text),
        ),
      );
      final first = store.taskRows().firstWhere((x) => x.id == id);
      expect(
        shown.data ?? shown.textSpan?.toPlainText(),
        isNot(first.cutNumber),
      );
    });

    testWidgets('완료 then 제출; submitting pauses, the cut stays', (t) async {
      final (store, timer, id) = await pick(t);
      await t.tap(find.byKey(const Key('timer-toggle')));
      await t.pump();
      expect(timer.running()?.taskId, id);
      await t.tap(find.byKey(const Key('timer-finish')));
      await t.pump();
      await t.pump();
      expect(find.text('제출'), findsWidgets);
      await t.tap(find.byKey(const Key('timer-finish')));
      await t.pump();
      await t.pump();
      expect(timer.running(), isNull, reason: 'submitting pauses');
      expect(find.byKey(const Key('timer-cut')), findsOneWidget);
      // A long press steps back.
      await t.longPress(find.byKey(const Key('timer-finish')));
      await t.pump();
      await t.tap(find.byKey(const Key('timer-back-done')));
      await t.pump();
      await t.pump();
      final row = store
          .taskRows(includeDone: true)
          .firstWhere((x) => x.id == id);
      expect(row.status.name, 'done');
    });

    testWidgets('a long press on the bar fixes the time by hand', (t) async {
      final (_, timer, id) = await pick(t);
      timer.addInterval(
        taskId: id,
        start: DateTime(2026, 11, 27, 9),
        stop: DateTime(2026, 11, 27, 13),
      );
      await t.longPress(find.byKey(const Key('timer-bar')));
      await t.pump();
      await t.pump();
      final stretch = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('stretch-delete-'),
      );
      expect(stretch, findsOneWidget);
      await t.tap(stretch);
      await t.pump();
      await t.pump();
      expect(stretch, findsNothing);
      expect(timer.workedOn(id), Duration.zero);
    });
  });
}
