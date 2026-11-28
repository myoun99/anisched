import 'package:anisched/src/controllers/unit_bundles.dart';
import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

/// 별빛 #07 part B: LO (one cut left, overdue) gets 原画 due in [days].
PartGroup addGenga(CatalogueStore s, {int days = 5}) {
  final lo = s.partGroups().firstWhere(
    (g) => g.workTitle == '별빛 정류장' && g.partLabel == 'B',
  );
  final genga = s.stages(lo.workId).firstWhere((x) => x.name == '원화').id;
  s.addTasksForPart(lo.partId!, genga);
  s.setPartDue(lo.partId!, genga, now.add(Duration(days: days)));
  return lo;
}

/// Hands in what is left of [lo] (its one open cut): the stage has
/// nothing left to work on, and shows only with `includeDone`.
void finishLo(CatalogueStore s, PartGroup lo) {
  for (final t in lo.tasks.where((t) => t.isOpen)) {
    s.setStatus(t.id, TaskStatus.submitted);
  }
}

Future<void> pumpShell(WidgetTester t, CatalogueStore store, AppView v) async {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: v,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('the list shows a bundle as one line that opens its stages', (
    t,
  ) async {
    final s = sampleCatalogue(now);
    final lo = addGenga(s);
    await pumpShell(t, s, AppView.list);
    final line = find.byKey(Key('line-bundle:part:${lo.partId}'));
    expect(line, findsOneWidget);
    expect(find.text('・원화', findRichText: true), findsNothing);
    final stages = s.partGroups().where((g) => g.partId == lo.partId);
    for (final g in stages) {
      expect(find.byKey(Key('line-${g.key}')), findsNothing);
    }
    await t.tap(line);
    await t.pump();
    for (final g in stages) {
      expect(find.byKey(Key('line-${g.key}')), findsOneWidget);
    }
    // A stage opens its own details.
    final genga = stages.last;
    await t.tap(find.byKey(Key('line-${genga.key}')));
    await t.pump();
    expect(find.byKey(Key('details-due-${genga.key}')), findsOneWidget);
    expect(find.byKey(Key('details-due-${lo.key}')), findsNothing);
  });

  testWidgets('a long press on a bundle picks every stage\'s cuts', (t) async {
    final s = sampleCatalogue(now);
    final lo = addGenga(s);
    await pumpShell(t, s, AppView.list);
    await t.longPress(find.byKey(Key('line-bundle:part:${lo.partId}')));
    await t.pump();
    final count = t.widget<Text>(find.byKey(const Key('picked-count')));
    expect(count.data, contains('8'));
  });

  test('one part at two stages is one bundle, stages in order', () {
    final s = sampleCatalogue(now);
    final lo = addGenga(s);
    final groups = s.partGroups();
    final bundles = bundleUnits(groups);
    expect(bundles.length, groups.length - 1);
    final b = bundles.singleWhere((b) => !b.single);
    expect([for (final g in b.stages) g.stageName], ['LO', '원화']);
    expect(b.key, 'bundle:part:${lo.partId}');
    expect(b.total, 8);
    expect(b.together.total, 8);
    expect(b.handed, 3); // LO's three handed-in cuts
    // A plain unit's bundle keeps the unit's own key.
    expect(bundles.firstWhere((b) => b.single).key, isNot(startsWith('b')));
  });

  test('the lead is the earliest deadline still to work on', () {
    final s = sampleCatalogue(now);
    finishLo(s, addGenga(s, days: 5));
    final b = bundleUnits(s.partGroups(includeDone: true))
        .singleWhere((b) => !b.single);
    // LO is overdue but all handed in (nothing left to work): 原画 leads.
    expect(b.lead.stageName, '원화');
  });

  test('of two stages with work left, the earlier deadline leads', () {
    final s = sampleCatalogue(now);
    // Part C: LO (open, due in 4 days) gets 原画 due in 9.
    final lo = s.partGroups().firstWhere(
      (g) => g.workTitle == '별빛 정류장' && g.partLabel == 'C',
    );
    final genga = s.stages(lo.workId).firstWhere((x) => x.name == '원화').id;
    s.addTasksForPart(lo.partId!, genga);
    s.setPartDue(lo.partId!, genga, now.add(const Duration(days: 9)));
    final b = bundleUnits(s.partGroups())
        .singleWhere((b) => b.key == 'bundle:part:${lo.partId}');
    expect(b.lead.stageName, 'LO');
  });

  test('with nothing left to work on, the first stage leads', () {
    final s = sampleCatalogue(now);
    final lo = addGenga(s);
    finishLo(s, lo);
    final b0 = bundleUnits(s.partGroups(includeDone: true))
        .singleWhere((b) => !b.single);
    for (final t in b0.stages.last.tasks) {
      s.setStatus(t.id, TaskStatus.submitted);
    }
    final b = bundleUnits(s.partGroups(includeDone: true))
        .singleWhere((b) => b.key == 'bundle:part:${lo.partId}');
    expect(b.lead.stageName, 'LO');
  });

  test('a bundle sits where its lead was; others keep their order', () {
    final s = sampleCatalogue(now);
    finishLo(s, addGenga(s, days: 30));
    final groups = s.partGroups(includeDone: true);
    final bundles = bundleUnits(groups);
    final leads = [for (final b in bundles) b.lead.key];
    final order = [for (final g in groups) g.key];
    final at = [for (final k in leads) order.indexOf(k)];
    expect(at, [...at]..sort());
    // Its 原画 is due last: the bundle moved after the LO's place.
    expect(bundles.last.single, isFalse);
  });

  test('a part bundles by part; a storyboard stays alone', () {
    final s = sampleCatalogue(now);
    final groups = s.partGroups();
    final board = groups.firstWhere((g) => g.kind == GroupKind.storyboard);
    expect(bundleKeyOf(board), board.key);
    final part = groups.firstWhere((g) => g.kind == GroupKind.part);
    expect(bundleKeyOf(part), 'part:${part.partId}');
  });

  // The timeline bundles as the list does: one row, every stage's bar on
  // it named by its stage; opened, the stages' own rows under it.
  testWidgets('the timeline shows a bundle as one row of stage bars', (
    t,
  ) async {
    chartView.value = const ChartView();
    final s = sampleCatalogue(now);
    final lo = addGenga(s);
    // LO's deadline is before its kickoff in the sample: give it a bar.
    s.setPartKickoff(lo.partId!, lo.stageId, DateTime(2026, 11, 15));
    await pumpShell(t, s, AppView.timeline);
    final key = 'bundle:part:${lo.partId}';
    final genga = s.partGroups().firstWhere(
      (g) => g.partId == lo.partId && g.stageName == '원화',
    );
    expect(find.byKey(Key('tl-label-$key')), findsOneWidget);
    expect(find.byKey(Key('tl-bar-${lo.key}')), findsNothing);
    final bars = [
      for (final g in [lo, genga]) find.byKey(Key('tl-stage-bar-${g.key}')),
    ];
    for (final b in bars) {
      expect(b, findsOneWidget);
    }
    // One row: the same height on screen; each named by its stage.
    expect(
      t.getRect(bars[0]).center.dy,
      moreOrLessEquals(t.getRect(bars[1]).center.dy),
    );
    expect(t.widget<ChartBar>(bars[0]).label, 'LO');
    expect(t.widget<ChartBar>(bars[1]).label, '원화');

    // Opened, the stages get rows of their own, as in the list.
    await t.tap(find.byKey(Key('tl-label-$key')));
    await t.pump();
    expect(find.byKey(Key('tl-bar-${lo.key}')), findsOneWidget);
    expect(find.byKey(Key('tl-bar-${genga.key}')), findsOneWidget);
  });
}
