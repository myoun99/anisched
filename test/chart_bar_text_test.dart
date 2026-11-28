import 'package:anisched/src/ui/fit_text.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bar of [days] days in a 10-day window 500 wide (50 a day).
Future<void> pumpBar(WidgetTester t, {required int days, bool ends = true}) =>
    t.pumpWidget(
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
              onDates: ends ? (a, b) {} : null,
            ),
          ),
        ),
      ),
    );

void main() {
  for (final ends in [true, false]) {
    testWidgets('the label gets the bar\'s whole width (ends: $ends)', (
      t,
    ) async {
      for (final days in [1, 3, 8]) {
        await pumpBar(t, days: days, ends: ends);
        final bar = days * 50.0;
        expect(t.getSize(find.byType(FitText)).width, bar);
        // Its left edge is the bar's: no padding, no grip's room.
        expect(
          t.getTopLeft(find.byType(FitText)).dx,
          t.getTopLeft(find.byType(ChartBar)).dx + 50,
        );
      }
    });
  }

  testWidgets('the end grips still move the dates over the label', (t) async {
    DateTime? end;
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 500,
            height: ChartBoard.rowExtent,
            child: ChartBar(
              window: ChartWindow(DateTime(2026, 11, 20), 10),
              start: DateTime(2026, 11, 21),
              end: DateTime(2026, 11, 23),
              color: Colors.blue,
              label: 'label',
              onDates: (a, b) => end = b,
            ),
          ),
        ),
      ),
    );
    await t.drag(find.byKey(const Key('bar-end')), const Offset(100, 0));
    await t.pump();
    expect((end!.month, end!.day), (11, 25));
  });
}
