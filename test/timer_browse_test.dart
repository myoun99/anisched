import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/format.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<(CatalogueStore, WorkTimerStore)> pumpShell(WidgetTester t) async {
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
  await t.pump();
  return (store, timer);
}

/// The timer bar's cut name.
String barCut(WidgetTester t) => t
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('timer-cut')),
        matching: find.byType(Text),
      ),
    )
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .join();

Future<void> tapKey(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pump();
}

int? depthOf(WidgetTester t) {
  for (var d = 4; d >= 0; d--) {
    final crumb = find.byKey(Key('browser-crumb-$d'));
    if (crumb.evaluate().isNotEmpty) return d;
  }
  return null;
}

void main() {
  testWidgets('an empty bar walks the catalogue down to a cut; ↑ goes up', (
    t,
  ) async {
    final (store, timer) = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    await tapKey(t, 'timer-cut');
    expect(find.byKey(const Key('browser')), findsOneWidget);
    await tapKey(t, 'browse-client-${g.clientName}');
    await tapKey(t, 'browse-work-${g.workId}');
    expect(depthOf(t), 2);
    // ↑: back to the client's works, then on down again.
    await tapKey(t, 'browser-up');
    expect(depthOf(t), 1);
    await tapKey(t, 'browse-work-${g.workId}');
    await tapKey(t, 'browse-episode-${g.episodeId}');
    await tapKey(t, 'browse-unit-${g.key}');
    final cut = cutUnits(g.tasks.where((x) => x.isOpen)).first;
    await tapKey(t, 'browse-cut-${cut.first.id}');
    expect(find.byKey(const Key('browser')), findsNothing);
    expect(barCut(t), taskLabel(cut.first));
    expect(store.timerTarget(), cut.first.id);
    expect(timer.running(), isNull, reason: 'picked, not started');
  });

  testWidgets('a search finds a cut from the top', (t) async {
    final (store, _) = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    final task = g.tasks.last;
    await tapKey(t, 'timer-cut');
    await t.enterText(find.byKey(const Key('browser-search')), taskLabel(task));
    await t.pump();
    await tapKey(t, 'browse-cut-${task.id}');
    expect(barCut(t), taskLabel(task));
  });

  testWidgets('the cut picker holds the unit\'s cuts only; the stage button '
      'moves to another stage', (t) async {
    final (store, _) = await pumpShell(t);
    // A part with two stages: its cuts taken on to another stage too.
    final g = store.partGroups().firstWhere((g) => g.kind == GroupKind.part);
    final stage = store.addStage(g.workId, '2원');
    for (final c in {for (final x in g.tasks) x.cutId!}) {
      store.addTask(stage, cutId: c);
    }
    final groups = store.partGroups();
    final other = groups.firstWhere(
      (o) =>
          o.key != g.key && o.episodeId == g.episodeId && o.partId == g.partId,
    );
    store.setTimerTarget(g.tasks.firstWhere((x) => x.isOpen).id);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          reader: SyncCatalogueReader(store),
          store: store,
          timer: WorkTimerStore(store.db, clock: () => now),
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    await t.pump();
    await tapKey(t, 'timer-cut');
    await t.pumpAndSettle();
    // Only this unit's cuts: none of another stage or episode.
    final mine = {for (final u in cutUnits(g.tasks)) unitText(u)};
    expect(find.byType(Dialog), findsOneWidget);
    for (final name in mine) {
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text(name)),
        findsOneWidget,
      );
    }
    for (final o in groups) {
      if (o.key == g.key) continue;
      for (final u in cutUnits(o.tasks)) {
        final name = unitText(u);
        if (mine.contains(name)) continue;
        expect(
          find.descendant(of: find.byType(Dialog), matching: find.text(name)),
          findsNothing,
          reason: '$name of ${o.key}',
        );
      }
    }
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    // The stage button: the other stage, the same cut if it has it.
    await tapKey(t, 'timer-stage');
    await t.pumpAndSettle();
    await t.tap(find.text(stageText(other.stageName)).last);
    await t.pumpAndSettle();
    final target = store.timerTarget();
    expect(other.tasks.any((x) => x.id == target), isTrue);
  });
}
