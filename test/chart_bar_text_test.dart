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
  test('a grip is at most 16, and at most half a day', () {
    expect(BarGrip.widthFor(50), 16);
    expect(BarGrip.widthFor(32), 16);
    expect(BarGrip.widthFor(20), 10);
    expect(BarGrip.widthFor(6), 3);
  });

  testWidgets('a fixed bar has no grips; its label gets the whole bar', (
    t,
  ) async {
    for (final days in [1, 3, 8]) {
      await pumpBar(t, days: days, ends: false);
      expect(find.byType(BarGrip), findsNothing);
      expect(t.getSize(find.byType(FitText)).width, days * 50.0);
    }
  });

  testWidgets('the label takes every pixel between the two grips', (t) async {
    for (final days in [1, 2, 8]) {
      await pumpBar(t, days: days);
      expect(find.byType(BarGrip), findsNWidgets(2));
      expect(t.getSize(find.byType(BarGrip).first).width, 16);
      expect(t.getSize(find.byType(FitText)).width, days * 50.0 - 32);
      expect(
        t.getTopLeft(find.byType(FitText)).dx,
        t.getTopRight(find.byType(BarGrip).first).dx,
      );
      expect(
        t.getTopRight(find.byType(FitText)).dx,
        t.getTopLeft(find.byType(BarGrip).last).dx,
      );
    }
  });

  testWidgets('zoomed out, a one-day bar is just its two grips', (t) async {
    // 20 a day: grips of 10, nothing left for the label.
    await pumpBar(t, days: 1, width: 200);
    final grips = find.byType(BarGrip);
    expect(grips, findsNWidgets(2));
    expect(t.getSize(grips.first).width, 10);
    expect(find.byType(FitText), findsNothing);
    final bar = t.getTopLeft(find.byType(ChartBar)).dx + 20;
    expect(t.getTopLeft(grips.first).dx, bar);
    expect(t.getTopRight(grips.last).dx, bar + 20);
    // Two days leave 20: enough for the label.
    await pumpBar(t, days: 2, width: 200);
    expect(t.getSize(find.byType(FitText)).width, 20);
  });

  testWidgets('dragging a grip moves that end', (t) async {
    DateTime? end;
    await pumpBar(t, days: 3, onDates: (a, b) => end = b);
    await t.drag(find.byKey(const Key('bar-end')), const Offset(100, 0));
    await t.pump();
    expect((end!.month, end!.day), (11, 25));
  });
}
