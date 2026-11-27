import 'package:anisched/src/core/size_class.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<void> pumpSheet(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: Scaffold(
        body: SheetView(
          parts: sampleCatalogue(now).partGroups(includeDone: true),
          now: now,
          layout: ScreenLayout.of(size.width, size.height),
        ),
      ),
    ),
  );
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
      await pumpSheet(t, size);
      expect(t.takeException(), isNull);
      expect(find.text('6파트 · 21건'), findsOneWidget);
    });
  }

  testWidgets('wide shows the progress column, medium drops it', (t) async {
    await pumpSheet(t, const Size(1280, 800));
    expect(find.text('진행'), findsOneWidget);
    await pumpSheet(t, const Size(800, 1280));
    expect(find.text('진행'), findsNothing);
  });

  testWidgets('a part opens to show its cuts', (t) async {
    await pumpSheet(t, const Size(1280, 800));
    expect(find.text('C012'), findsNothing);
    await t.tap(find.byKey(Key('caret-${partKey('A', '원화')}')));
    await t.pump();
    expect(find.text('C012'), findsOneWidget);
    expect(find.text('C021'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('filtering by status narrows the parts', (t) async {
    await pumpSheet(t, const Size(1280, 800));
    await t.tap(find.text('리테이크').first);
    await t.pump();
    expect(find.textContaining('4파트'), findsOneWidget);
  });

  testWidgets('narrow opens a part too', (t) async {
    await pumpSheet(t, const Size(412, 915));
    await t.tap(find.byKey(Key('caret-${partKey('A', '원화')}')));
    await t.pump();
    expect(find.text('C015'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

/// The group key of 별빛 정류장's part [label] × [stage] in the sample.
String partKey(String label, String stage) => sampleCatalogue(now)
    .partGroups(includeDone: true)
    .firstWhere(
      (g) =>
          g.workTitle == '별빛 정류장' &&
          g.partLabel == label &&
          g.stageName == stage,
    )
    .key;
