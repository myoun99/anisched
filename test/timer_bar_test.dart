import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  testWidgets('a cut tapped in the list starts the timer; stop stops it', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
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
    expect(find.byKey(const Key('timer-resume')), findsOneWidget);
    final g = store.partGroups().first;
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    final task = g.tasks.first;
    await t.tap(find.byKey(Key('cut-${task.id}')));
    await t.pump();
    expect(timer.running()?.taskId, task.id);
    expect(find.byKey(const Key('timer-stop')), findsOneWidget);
    await t.tap(find.byKey(const Key('timer-stop')));
    await t.pump();
    expect(timer.running(), isNull);
    expect(find.byKey(const Key('timer-resume')), findsOneWidget);
  });
}
