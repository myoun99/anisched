import 'package:anisched/src/core/size_class.dart';
import 'package:anisched/src/models/lanes.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:anisched/src/ui/views/timeline_view.dart';
import 'package:anisched/src/ui/views/work_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

const devices = {
  'desktop': Size(1440, 900),
  'tablet portrait': Size(800, 1280),
  'phone portrait': Size(412, 915),
  'small phone portrait': Size(390, 844),
  'phone landscape': Size(915, 412),
};

Future<void> pumpIn(WidgetTester t, Size size, Widget child) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() => chartView.value = const ChartView());

  test('the window puts today a few days in, wider on bigger screens', () {
    final w = ChartWindow.around(now, SizeClass.wide);
    final n = ChartWindow.around(now, SizeClass.narrow);
    expect(w.days, greaterThan(n.days));
    expect(w.indexOf(now), 11);
    expect(n.indexOf(now), 3);
    expect(
      ChartWindow.around(now, SizeClass.narrow, shift: 7).indexOf(now),
      -4,
    );
  });

  group('timeline', () {
    devices.forEach((name, size) {
      testWidgets('$name lays out without overflow', (t) async {
        final store = sampleCatalogue(now);
        await pumpIn(
          t,
          size,
          TimelineView(
            parts: store.partGroups(),
            now: now,
            layout: ScreenLayout.of(size.width, size.height),
          ),
        );
        expect(t.takeException(), isNull);
        expect(find.text('D-day'), findsWidgets);
      });
    });

    testWidgets('dragging a bar end reports the new deadline', (t) async {
      final store = sampleCatalogue(now);
      final groups = store.partGroups();
      final w = ChartWindow.around(now, SizeClass.wide);
      final g = groups.firstWhere(
        (g) =>
            g.dueAt != null &&
            g.kickoffAt != null &&
            w.indexOf(g.kickoffAt!) >= 0 &&
            w.indexOf(g.dueAt!) < 25,
      );
      (PartGroup, DateTime, DateTime)? got;
      await pumpIn(
        t,
        const Size(1440, 900),
        TimelineView(
          parts: [g],
          now: now,
          layout: ScreenLayout.of(1440, 900),
          onSchedule: (g, k, d) => got = (g, k, d),
        ),
      );
      final handle = find.descendant(
        of: find.byKey(Key('tl-bar-${g.key}')),
        matching: find.byKey(const Key('bar-end')),
      );
      const dayWidth = (1440 - 250) / 35;
      await t.drag(handle, const Offset(dayWidth * 3, 0));
      await t.pump();
      expect(got, isNotNull);
      expect(chartView.value.shift, 0, reason: 'a bar drag must not scroll');
      expect(got!.$3, chartDay(g.dueAt!).add(const Duration(days: 3)));
      expect(got!.$2, chartDay(g.kickoffAt!));
    });
  });

  group('work lanes', () {
    LaneLayout layoutOf(CatalogueStore s) =>
        s.calendarLayout(basis: CalendarBasis.work).layout;

    devices.forEach((name, size) {
      testWidgets('$name shows lanes and overflow rows', (t) async {
        final store = sampleCatalogue(now);
        final lanes = layoutOf(store);
        await pumpIn(
          t,
          size,
          WorkView(
            lanes: lanes,
            parts: {for (final g in store.partGroups()) g.key: g},
            now: now,
            layout: ScreenLayout.of(size.width, size.height),
          ),
        );
        expect(t.takeException(), isNull);
        expect(find.text('라인 1'), findsOneWidget);
        expect(find.text('라인 2'), findsOneWidget);
        if (lanes.overflow.isNotEmpty) {
          expect(find.text('넘침'), findsWidgets);
        }
      });
    });

    testWidgets('a long-press drag onto another lane pins the bar', (t) async {
      final store = sampleCatalogue(now);
      final lanes = layoutOf(store);
      final key = lanes.spans.firstWhere((s) => lanes.laneOf[s.key] == 0).key;
      (String, int)? pinned;
      await pumpIn(
        t,
        const Size(1440, 900),
        WorkView(
          lanes: lanes,
          parts: {for (final g in store.partGroups()) g.key: g},
          now: now,
          layout: ScreenLayout.of(1440, 900),
          onPin: (k, l) => pinned = (k, l),
        ),
      );
      final bar = find.byKey(Key('work-bar-$key'));
      final face = find.descendant(
        of: bar,
        matching: find.byType(LongPressDraggable<String>),
      );
      final from = t.getCenter(face);
      final to = t.getCenter(find.byKey(const Key('lane-1')));
      final g = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 600));
      await g.moveTo(Offset(from.dx, to.dy));
      await t.pump();
      await g.up();
      await t.pump();
      expect(pinned, (key, 1));
    });
  });

  group('scroll and zoom', () {
    Future<void> pumpTimeline(WidgetTester t) async {
      final store = sampleCatalogue(now);
      await pumpIn(
        t,
        const Size(1440, 900),
        TimelineView(
          parts: store.partGroups(),
          now: now,
          layout: ScreenLayout.of(1440, 900),
        ),
      );
    }

    testWidgets('dragging empty space scrolls by whole days', (t) async {
      await pumpTimeline(t);
      const dayWidth = (1440 - 250) / 35;
      await t.dragFrom(
        const Offset(1300, 600),
        const Offset(-dayWidth * 5 - 2, 0),
      );
      await t.pump();
      expect(chartView.value.shift, 5);
      expect(
        ChartWindow.of(now, SizeClass.wide, chartView.value).indexOf(now),
        6,
      );
    });

    testWidgets('zoom buttons and Ctrl + wheel change the days shown', (
      t,
    ) async {
      await pumpTimeline(t);
      await t.tap(find.byKey(const Key('chart-zoom-in')));
      await t.pump();
      expect(chartView.value.days, 28);
      await t.tap(find.byKey(const Key('chart-zoom-out')));
      await t.pump();
      expect(chartView.value.days, 35);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(900, 500),
          scrollDelta: Offset(0, 40),
        ),
      );
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(chartView.value.days, 49);
      expect(find.text('49'), findsNothing);
    });

    testWidgets('a pinch zooms', (t) async {
      await pumpTimeline(t);
      final a = await t.startGesture(const Offset(700, 600));
      final b = await t.startGesture(const Offset(900, 600), pointer: 2);
      await a.moveTo(const Offset(600, 600));
      await b.moveTo(const Offset(1000, 600));
      await t.pump();
      await a.up();
      await b.up();
      await t.pump();
      expect(chartView.value.days, lessThan(35));
    });
  });
}
