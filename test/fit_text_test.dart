import 'package:anisched/src/ui/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a word that fits is left alone', () {
    expect(fitWord(width: 50, gaps: 4, room: 50), (
      spacing: 0.0,
      scaleX: 1.0,
      cut: false,
    ));
  });

  test('letter gaps give way first, a quarter pixel at a time', () {
    final f = fitWord(width: 52, gaps: 4, room: 50);
    expect(f.spacing, -0.5);
    expect(f.scaleX, 1);
    expect(f.cut, isFalse);
  });

  test('then the word narrows sideways, never under the floor', () {
    final f = fitWord(width: 60, gaps: 4, room: 50);
    expect(f.spacing, -maxGapTightening);
    expect(f.scaleX, lessThan(1));
    expect(f.scaleX, greaterThanOrEqualTo(minScaleX));
    expect(60 - 4 * maxGapTightening, greaterThan(50));
    expect((60 - 4) * f.scaleX, lessThanOrEqualTo(50));
    expect(f.cut, isFalse);
  });

  test('past the floor it is cut from the right', () {
    final f = fitWord(width: 200, gaps: 9, room: 50);
    expect(f.scaleX, minScaleX);
    expect(f.cut, isTrue);
  });

  testWidgets('a cut word shows itself whole on hover', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 40, child: FitText('별빛 정류장 #07 · 원화 · 4 cut')),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.byType(Tooltip), findsOneWidget);
    final roomy = FitText('LO');
    await t.pumpWidget(
      MaterialApp(
        home: Center(child: SizedBox(width: 200, child: roomy)),
      ),
    );
    expect(find.byType(Tooltip), findsNothing);
  });
}
