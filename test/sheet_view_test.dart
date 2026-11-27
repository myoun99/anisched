import 'package:anisched/src/core/size_class.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<List<PartGroup>> pumpSheet(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = sampleCatalogue(now);
  final groups = store.partGroups();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: Scaffold(
        body: SheetView(
          parts: groups,
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
    expect(find.text('C012'), findsNothing);
    expect(find.text('¥18,000'), findsNothing);
    await t.tap(find.byKey(Key('line-${a.key}')));
    await t.pump();
    expect(find.byKey(Key('details-${a.key}')), findsOneWidget);
    expect(find.text('C012'), findsOneWidget);
    expect(find.text('¥18,000'), findsOneWidget);
    await t.tap(find.byKey(Key('line-${a.key}')));
    await t.pump();
    expect(find.text('C012'), findsNothing);
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
}
