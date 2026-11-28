import 'package:anisched/src/ui/fit_text.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bar of [days] days from the 21st in a 10-day window 500 wide (50 a
/// day), the bar starting at x = 50.
Future<void> pumpBar(
  WidgetTester t, {
  required int days,
  bool ends = true,
  bool selected = false,
  void Function(DateTime, DateTime)? onDates,
}) => t.pumpWidget(
  MaterialApp(
    home: Center(
      child: SizedBox(
        width: 500,
        height: ChartBoard.rowExtent,
        child: ChartBar(
          window: ChartWindow(DateTime(2026, 11, 20), 10),
          start: DateTime(2026, 11, 21),
          end: DateTime(2026, 11, 20 + days),
          color: Colors.blue,
          label: 'A long label that never fits in a short bar',
          selected: selected,
          onDates: ends ? (onDates ?? (a, b) {}) : null,
        ),
      ),
    ),
  ),
);

double barLeft(WidgetTester t) => t.getTopLeft(find.byType(ChartBar)).dx + 50;

void main() {
  tearDown(() => shortBarGrips = ShortBarGrips.outside);

  testWidgets('a fixed bar has no grips; its label gets the whole bar', (
    t,
  ) async {
    for (final days in [1, 3, 8]) {
      await pumpBar(t, days: days, ends: false);
      expect(find.byType(BarGrip), findsNothing);
      expect(t.getSize(find.byType(FitText)).width, days * 50.0);
      expect(t.getTopLeft(find.byType(FitText)).dx, barLeft(t));
    }
  });

  testWidgets('the label takes every pixel between the two grips', (t) async {
    for (final days in [2, 3, 8]) {
      await pumpBar(t, days: days);
      expect(find.byType(BarGrip), findsNWidgets(2));
      expect(
        t.getSize(find.byType(FitText)).width,
        days * 50.0 - 2 * BarGrip.width,
      );
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

  testWidgets('a short bar keeps its grips just outside its ends', (t) async {
    await pumpBar(t, days: 1);
    expect(t.getSize(find.byType(FitText)).width, 50);
    expect(t.getTopRight(find.byType(BarGrip).first).dx, barLeft(t));
    expect(t.getTopLeft(find.byType(BarGrip).last).dx, barLeft(t) + 50);
  });

  testWidgets('or, the other proposal, only while it is the opened bar', (
    t,
  ) async {
    shortBarGrips = ShortBarGrips.whenSelected;
    await pumpBar(t, days: 1);
    expect(find.byType(BarGrip), findsNothing);
    await pumpBar(t, days: 1, selected: true);
    expect(find.byType(BarGrip), findsNWidgets(2));
    // Long bars keep theirs either way.
    await pumpBar(t, days: 3);
    expect(find.byType(BarGrip), findsNWidgets(2));
  });

  testWidgets('dragging a grip moves that end', (t) async {
    DateTime? end;
    await pumpBar(t, days: 3, onDates: (a, b) => end = b);
    await t.drag(find.byKey(const Key('bar-end')), const Offset(100, 0));
    await t.pump();
    expect((end!.month, end!.day), (11, 25));
  });
}
