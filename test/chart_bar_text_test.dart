import 'package:anisched/src/ui/fit_text.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bar of [days] days from the 21st in a 10-day window [width] wide,
/// the bar starting at the 2nd day.
Future<void> pumpBar(
  WidgetTester t, {
  required int days,
  double width = 500,
  bool ends = true,
  void Function(DateTime, DateTime)? onDates,
}) => t.pumpWidget(
  MaterialApp(
    home: Center(
      child: SizedBox(
        width: width,
        height: ChartBoard.rowExtent,
        child: ChartBar(
          window: ChartWindow(DateTime(2026, 11, 20), 10),
          start: DateTime(2026, 11, 21),
          end: DateTime(2026, 11, 20 + days),
          color: Colors.blue,
          label: 'A long label that never fits in a short bar',
          onDates: ends ? (onDates ?? (a, b) {}) : null,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a fixed bar has no grips; its label gets the whole bar', (
    t,
  ) async {
    for (final days in [1, 3, 8]) {
      await pumpBar(t, days: days, ends: false);
      expect(find.byType(BarGrip), findsNothing);
      expect(t.getSize(find.byType(FitText)).width, days * 50.0);
    }
  });

  // Anicel's run edges (유저 2026-11-28): the start grip is the lower half
  // of the bar's left end, the end grip the upper half of its right end,
  // both always inside the bar; the label runs end to end between them.
  testWidgets('the grips are corners inside the bar; the label is the bar', (
    t,
  ) async {
    for (final days in [1, 2, 8]) {
      await pumpBar(t, days: days);
      final grips = find.byType(BarGrip);
      expect(grips, findsNWidgets(2));
      final bar = t.getRect(find.byKey(const Key('bar-face')));
      final start = t.getRect(grips.first);
      final end = t.getRect(grips.last);
      expect(start.width, 16);
      expect(start.height, closeTo(bar.height / 2, 0.01));
      expect(start.left, bar.left);
      expect(start.bottom, bar.bottom);
      expect(start.center.dy, greaterThan(bar.center.dy));
      expect(end.right, bar.right);
      expect(end.top, bar.top);
      expect(end.center.dy, lessThan(bar.center.dy));
      expect(t.getSize(find.byType(FitText)).width, closeTo(bar.width, 0.01));
    }
  });

  testWidgets('zoomed out, a short bar keeps both grips inside it', (t) async {
    // 20 a day: a one-day bar is 20, short of two grips side by side.
    await pumpBar(t, days: 1, width: 200);
    final bar = t.getRect(find.byKey(const Key('bar-face')));
    expect(bar.width, 20);
    for (var g = 0; g < 2; g++) {
      final r = t.getRect(find.byType(BarGrip).at(g));
      expect(r.left, greaterThanOrEqualTo(bar.left - 0.01));
      expect(r.right, lessThanOrEqualTo(bar.right + 0.01));
      expect(r.top, greaterThanOrEqualTo(bar.top - 0.01));
      expect(r.bottom, lessThanOrEqualTo(bar.bottom + 0.01));
    }
    // Diagonal: one below the middle, one above.
    expect(
      t.getRect(find.byType(BarGrip).first).top,
      greaterThanOrEqualTo(t.getRect(find.byType(BarGrip).last).bottom - 0.01),
    );
    // Narrower than a grip: the grips take the bar's width, still inside.
    await pumpBar(t, days: 1, width: 100);
    expect(t.getSize(find.byType(BarGrip).first).width, 10);
    expect(find.byKey(const Key('bar-end')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('bar-start')).hitTestable(), findsOneWidget);
  });

  testWidgets('a bar narrower than 8 hides its label', (t) async {
    await pumpBar(t, days: 1, width: 70);
    expect(find.byType(BarGrip), findsNWidgets(2));
    expect(find.byType(FitText), findsNothing);
  });

  testWidgets('dragging a grip moves that end', (t) async {
    DateTime? end;
    await pumpBar(t, days: 3, onDates: (a, b) => end = b);
    await t.drag(find.byKey(const Key('bar-end')), const Offset(100, 0));
    await t.pump();
    expect((end!.month, end!.day), (11, 25));
  });

  testWidgets('a bar fills its row but for a hair', (t) async {
    await pumpBar(t, days: 3);
    final h = t.getSize(find.byKey(const Key('bar-face'))).height;
    expect(h, greaterThanOrEqualTo(ChartBoard.rowExtent - 4));
    expect(h, lessThan(ChartBoard.rowExtent), reason: 'the row shows a hair');
  });
}
