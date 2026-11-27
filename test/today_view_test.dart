import 'package:anisched/src/core/size_class.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/today_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<WorkTimerStore> pumpToday(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = sampleCatalogue(now);
  final timer = WorkTimerStore(store.db, clock: () => now);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: Scaffold(
        body: TodayScreen(
          reader: SyncCatalogueReader(store),
          timer: timer,
          clock: () => now,
          layout: ScreenLayout.of(size.width, size.height),
        ),
      ),
    ),
  );
  await tester.pump();
  return timer;
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
      await pumpToday(t, size);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('cuts-today')), findsOneWidget);
      expect(find.byKey(const Key('timer-clock')), findsOneWidget);
    });
  }

  testWidgets('tapping a cut starts the timer on it; stop stops it', (t) async {
    final timer = await pumpToday(t, const Size(1280, 800));
    expect(find.byKey(const Key('timer-stop')), findsNothing);
    await t.tap(find.textContaining('A파트', findRichText: true).first);
    await t.pump();
    await t.tap(find.text('C012'));
    await t.pump();
    expect(timer.running()?.taskId, isNotNull);
    expect(find.byKey(const Key('timer-stop')), findsOneWidget);
    expect(find.text('C012'), findsNWidgets(2));
    await t.tap(find.byKey(const Key('timer-stop')));
    await t.pump();
    expect(timer.running(), isNull);
    expect(find.byKey(const Key('timer-resume')), findsOneWidget);
  });

  testWidgets('usual pace stays folded until opened', (t) async {
    await pumpToday(t, const Size(1280, 800));
    expect(find.textContaining('컷/일'), findsNothing);
    await t.tap(find.byKey(const Key('fold-pace')));
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
