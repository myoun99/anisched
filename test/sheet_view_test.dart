import 'package:anisched/src/core/size_class.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/sheet_view.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<List<PartGroup>> pumpSheet(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = sampleCatalogue(now);
  final groups = store.partGroups(includeDone: true);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: Scaffold(
        body: SheetView(
          parts: groups,
          signals: store.signals(includeDone: true),
          now: now,
          layout: ScreenLayout.of(size.width, size.height),
          paceOf: store.paceOf,
        ),
      ),
    ),
  );
  return groups;
}

PartGroup part(List<PartGroup> gs, String work, String label, String stage) =>
    gs.firstWhere(
      (g) =>
          g.workTitle == work && g.partLabel == label && g.stageName == stage,
    );

void main() {
  setUp(() {
    Folds.cutsInDetails.value = true;
    Folds.newCuts.value = true;
    Folds.savedCuts.value = true;
  });

  for (final size in const [
    Size(1440, 900),
    Size(1280, 800),
    Size(800, 1280),
    Size(915, 412),
    Size(412, 915),
  ]) {
    testWidgets('lays out without overflow at $size', (t) async {
      final gs = await pumpSheet(t, size);
      expect(t.takeException(), isNull);
      final a = part(gs, '별빛 정류장', 'A', '원화');
      await t.tap(find.byKey(Key('line-${a.key}')));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('done parts are hidden until asked for', (t) async {
    final gs = await pumpSheet(t, const Size(1280, 800));
    final done = part(gs, '별빛 정류장', 'B', 'LO');
    expect(find.byKey(Key('line-${done.key}')), findsNothing);
    await t.tap(find.byKey(const Key('toggle-done')));
    await t.pump();
    expect(find.byKey(Key('line-${done.key}')), findsOneWidget);
  });

  testWidgets('a line shows no detail until it opens', (t) async {
    final gs = await pumpSheet(t, const Size(1280, 800));
    final a = part(gs, '별빛 정류장', 'A', '원화');
    expect(find.textContaining('C012', findRichText: true), findsNothing);
    expect(find.textContaining('¥18,000', findRichText: true), findsNothing);
    await t.tap(find.byKey(Key('line-${a.key}')));
    await t.pump();
    expect(find.byKey(Key('details-${a.key}')), findsOneWidget);
    expect(find.textContaining('C012', findRichText: true), findsWidgets);
    expect(find.textContaining('¥18,000', findRichText: true), findsOneWidget);
    await t.tap(find.byKey(Key('line-${a.key}')));
    await t.pump();
    expect(find.textContaining('C012', findRichText: true), findsNothing);
  });

  testWidgets('the work menu narrows to one work', (t) async {
    final gs = await pumpSheet(t, const Size(1280, 800));
    await t.tap(find.byKey(const Key('work-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('마법소녀 리코').last);
    await t.pumpAndSettle();
    final riko = part(gs, '마법소녀 리코', 'B', '원화 작감 수정');
    final star = part(gs, '별빛 정류장', 'A', '원화');
    expect(find.byKey(Key('line-${riko.key}')), findsOneWidget);
    expect(find.byKey(Key('line-${star.key}')), findsNothing);
  });

  testWidgets('a plan past its deadline puts a dot by the D label', (t) async {
    final gs = await pumpSheet(t, const Size(1280, 800));
    final c = part(gs, '별빛 정류장', 'C', 'LO');
    final line = find.byKey(Key('line-${c.key}'));
    expect(
      find.descendant(of: line, matching: find.byKey(const Key('plan-dot'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.text('D-4')),
      findsOneWidget,
    );
    await t.tap(line);
    await t.pump();
    expect(find.text('실 작업 끝이 마감보다 늦음'), findsOneWidget);
  });

  testWidgets('opened details show the production and work dates', (t) async {
    final gs = await pumpSheet(t, const Size(1280, 800));
    final g = part(gs, '별빛 정류장', 'C', 'LO');
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    final d = find.byKey(Key('details-${g.key}'));
    for (final k in ['제작', '실 작업']) {
      expect(
        find.descendant(
          of: d,
          matching: find.textContaining(k, findRichText: true),
        ),
        findsWidgets,
      );
    }
  });

  testWidgets('cut chips fold away and stay folded for the next unit', (
    t,
  ) async {
    Folds.cutsInDetails.value = false;
    final gs = await pumpSheet(t, const Size(1280, 800));
    final g = part(gs, '별빛 정류장', 'C', 'LO');
    await t.tap(find.byKey(Key('line-${g.key}')));
    await t.pump();
    final chip = find.byKey(Key('cut-${g.tasks.first.id}'));
    expect(chip, findsNothing);
    await t.tap(find.byKey(Key('fold-cuts-${g.key}')));
    await t.pump();
    expect(Folds.cutsInDetails.value, isTrue);
  });
}
