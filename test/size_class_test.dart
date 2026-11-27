import 'package:anisched/src/core/size_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SizeClass.ofWidth', () {
    test('splits at 700 and 1100', () {
      expect(SizeClass.ofWidth(412), SizeClass.narrow);
      expect(SizeClass.ofWidth(699.9), SizeClass.narrow);
      expect(SizeClass.ofWidth(700), SizeClass.medium);
      expect(SizeClass.ofWidth(1099), SizeClass.medium);
      expect(SizeClass.ofWidth(1100), SizeClass.wide);
      expect(SizeClass.ofWidth(1440), SizeClass.wide);
    });
  });

  group('ScreenLayout', () {
    test('reads orientation from the aspect', () {
      expect(ScreenLayout.of(915, 412).landscape, isTrue);
      expect(ScreenLayout.of(800, 1280).landscape, isFalse);
    });

    test('detail panel goes beside on wide and sideways medium', () {
      expect(ScreenLayout.of(1280, 800).detailBeside, isTrue);
      expect(ScreenLayout.of(915, 412).detailBeside, isTrue);
      expect(ScreenLayout.of(800, 1280).detailBeside, isFalse);
      expect(ScreenLayout.of(412, 915).detailBeside, isFalse);
    });
  });
}
