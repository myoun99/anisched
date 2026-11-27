import 'package:anisched/src/core/size_class.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/board_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<List<PartGroup>> pumpBoard(WidgetTester tester, Size size) async {
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
        body: BoardView(
          parts: groups,
          signals: store.signals(),
          layout: ScreenLayout.of(size.width, size.height),
        ),
      ),
    ),
  );
  return groups;
}

void main() {
  for (final size in const [
    Size(1440, 900),
    Size(1280, 800),
    Size(800, 1280),
    Size(915, 412),
    Size(412, 915),
  ]) {
    testWidgets('lays out without overflow at $size', (t) async {
      await pumpBoard(t, size);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('columns follow deadline urgency by default', (t) async {
    final gs = await pumpBoard(t, const Size(1280, 800));
    for (final l in ['지난 것', '3일 안', '2주 안', '그 뒤', '넘김']) {
      expect(find.byKey(Key('column-$l')), findsOneWidget);
    }
    final a = gs.firstWhere(
      (g) => g.workTitle == '별빛 정류장' && g.partLabel == 'A',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('column-3일 안')),
        matching: find.byKey(Key('card-${a.key}')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the basis menu switches to status columns', (t) async {
    await pumpBoard(t, const Size(1280, 800));
    await t.tap(find.byKey(const Key('board-basis')));
    await t.pumpAndSettle();
    await t.tap(find.text('상태 순').last);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('column-리테이크')), findsOneWidget);
    expect(find.byKey(const Key('column-지난 것')), findsNothing);
  });

  testWidgets('a card opens to its details', (t) async {
    final gs = await pumpBoard(t, const Size(1280, 800));
    final a = gs.firstWhere(
      (g) => g.workTitle == '별빛 정류장' && g.partLabel == 'A',
    );
    expect(find.textContaining('C012', findRichText: true), findsNothing);
    await t.tap(find.byKey(Key('card-${a.key}')));
    await t.pump();
    expect(find.textContaining('C012', findRichText: true), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('narrow shows one column at a time', (t) async {
    await pumpBoard(t, const Size(412, 915));
    expect(find.byKey(const Key('board-tab-0')), findsOneWidget);
    await t.tap(find.byKey(const Key('board-tab-1')));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
