import 'package:anisched/src/services/catalogue_reader.dart';
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
    expect(find.text('0:00:00'), findsOneWidget);

    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    expect(timer.running()?.taskId, task.id);
    now = now.add(const Duration(minutes: 5));
    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    expect(timer.running(), isNull);
    expect(find.text('0:05:00'), findsOneWidget, reason: 'paused keeps total');

    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    now = now.add(const Duration(minutes: 2));
    await t.tap(find.byKey(const Key('timer-toggle')));
    await t.pump();
    expect(find.text('0:07:00'), findsOneWidget);
  });
}
