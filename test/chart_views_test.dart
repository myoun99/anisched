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

// The narrowest and the shortest screens; wider ones have more room and
// are laid out by the other widget tests.
const devices = {
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

  group('day labels', () {
    final w = ChartWindow(DateTime.utc(2026, 11, 2), 70);

    test('every day while a number fits, sparser only when it does not', () {
      expect(DayLabels(w, 20, 13).step, 1);
      expect(DayLabels(w, 19, 13).step, 1, reason: 'just fits: kept');
      expect(DayLabels(w, 18, 13).step, 2);
      expect(DayLabels(w, 3, 13).step, 7);
    });

    test('numbered days stay put while the window scrolls', () {
      final a = DayLabels(w, 9, 13);
      final b = DayLabels(
        ChartWindow(w.start.add(const Duration(days: 1)), 70),
        9,
        13,
      );
      for (var i = 2; i < 60; i++) {
        expect(b.labelled(i - 1), a.labelled(i), reason: 'day $i');
        expect(b.shaded(i - 1), a.shaded(i), reason: 'day $i');
      }
    });

    test('a band runs from one number to the next, alternating', () {
      final l = DayLabels(w, 10, 13); // every 2 days
      expect(l.step, 2);
      final firsts = [
        for (var i = 0; i < 20; i++)
          if (l.labelled(i)) i,
      ];
      for (var k = 0; k + 1 < firsts.length; k++) {
        final band = l.shaded(firsts[k]);
        for (var i = firsts[k]; i < firsts[k + 1]; i++) {
          expect(l.shaded(i), band);
        }
        expect(l.shaded(firsts[k + 1]), isNot(band));
      }
      final weekly = DayLabels(w, 3, 13);
      expect(weekly.step, 7);
      for (var i = 1; i < 70; i++) {
        if (weekly.labelled(i)) {
          expect(w.dayAt(i).weekday, DateTime.monday);
        }
      }
    });
  });

  test('zoom stays between a week and fifteen weeks', () {
    expect(const ChartView().zoomed(3).days, ChartView.minDays);
    expect(const ChartView().zoomed(500).days, ChartView.maxDays);
    expect(const ChartView(days: 105).stepped(105, zoomIn: false).days, 105);
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
            !g.dueAt!.isBefore(g.kickoffAt!) &&
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

    testWidgets('dragging the zoom right zooms in, left zooms out', (t) async {
      await pumpTimeline(t);
      final zoom = find.byKey(const Key('chart-zoom'));
      await t.drag(zoom, const Offset(ZoomDrag.stepPixels * 2 + 4, 0));
      await t.pump();
      expect(chartView.value.days, 21, reason: 'two steps in from 35');
      await t.drag(zoom, const Offset(-ZoomDrag.stepPixels * 3 - 4, 0));
      await t.pump();
      expect(chartView.value.days, 49, reason: 'three steps out');
      expect(find.text('49일'), findsOneWidget);
    });

    testWidgets('Ctrl + wheel zooms the date area', (t) async {
      await pumpTimeline(t);
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
    });

    testWidgets('Space + drag pans, even over a bar', (t) async {
      final store = sampleCatalogue(now);
      final groups = store.partGroups();
      (PartGroup, DateTime, DateTime)? moved;
      await pumpIn(
        t,
        const Size(1440, 900),
        TimelineView(
          parts: groups,
          now: now,
          layout: ScreenLayout.of(1440, 900),
          onSchedule: (g, a, b) => moved = (g, a, b),
        ),
      );
      const dayWidth = (1440 - 250) / 35;
      final withBar = groups.firstWhere(
        (g) => g.kickoffAt != null && !g.dueAt!.isBefore(g.kickoffAt!),
      );
      final bar = find.byKey(Key('tl-bar-${withBar.key}'));
      await t.sendKeyDownEvent(LogicalKeyboardKey.space);
      await t.pump();
      final g = await t.startGesture(
        t.getCenter(bar),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await g.moveBy(const Offset(-dayWidth * 3 - 2, 0));
      await g.up();
      await t.sendKeyUpEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(chartView.value.shift, 3);
      expect(moved, isNull, reason: 'the bar did not move');
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

  group('layers', () {
    testWidgets('dragging a bar end redraws only the preview layer', (t) async {
      final store = sampleCatalogue(now);
      final g = store.partGroups().firstWhere(
        (g) =>
            g.dueAt != null &&
            g.kickoffAt != null &&
            !g.dueAt!.isBefore(g.kickoffAt!),
      );
      await pumpIn(
        t,
        const Size(1440, 900),
        TimelineView(
          parts: store.partGroups(),
          now: now,
          layout: ScreenLayout.of(1440, 900),
          onSchedule: (_, _, _) {},
        ),
      );
      final handle = find.descendant(
        of: find.byKey(Key('tl-bar-${g.key}')),
        matching: find.byKey(const Key('bar-end')),
      );
      final gesture = await t.startGesture(t.getCenter(handle));
      await gesture.moveBy(const Offset(30, 0));
      await t.pump();
      ChartPaints.reset();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(34, 0));
        await t.pump();
      }
      expect(ChartPaints.preview, greaterThanOrEqualTo(4));
      expect(ChartPaints.barBuilds, 0, reason: 'the bar itself is not rebuilt');
      expect(ChartPaints.background, 0, reason: 'background is its own layer');
      expect(ChartPaints.today, 0, reason: "today's column is its own layer");
      await gesture.up();
      await t.pump();
    });

    testWidgets('new rows leave the background and today alone', (t) async {
      final store = sampleCatalogue(now);
      final groups = store.partGroups();
      Widget view(List<PartGroup> parts) => TimelineView(
        parts: parts,
        now: now,
        layout: ScreenLayout.of(1440, 900),
      );
      await pumpIn(t, const Size(1440, 900), view(groups));
      ChartPaints.reset();
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          scrollBehavior: const AlwaysScrollbarBehavior(),
          home: Scaffold(body: view(groups.sublist(1))),
        ),
      );
      await t.pump();
      expect(ChartPaints.background, 0);
      expect(ChartPaints.today, 0);
      chartView.value = chartView.value.scrolled(1);
      await t.pump();
      expect(ChartPaints.background, greaterThan(0), reason: 'dates moved');
    });
  });
}
