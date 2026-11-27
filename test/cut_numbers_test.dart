import 'package:anisched/src/models/cut_numbers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> nums(String s) => parseCutNumbers(s).numbers;

  test('a range with a tilde or en dash, end with or without the prefix', () {
    expect(nums('C100~C103'), ['C100', 'C101', 'C102', 'C103']);
    expect(nums('C100–103'), ['C100', 'C101', 'C102', 'C103']);
    expect(nums('C100 ~ C101'), ['C100', 'C101']);
    expect(nums('C100〜C101'), ['C100', 'C101']);
    expect(nums('12..14'), ['12', '13', '14']);
  });

  test('zero padding follows the start', () {
    expect(nums('C098~C101'), ['C098', 'C099', 'C100', 'C101']);
    expect(nums('008~010'), ['008', '009', '010']);
  });

  test('lists mix ranges and single cuts; duplicates drop out', () {
    expect(nums('C100, C102~C104 C110、C103'), [
      'C100',
      'C102',
      'C103',
      'C104',
      'C110',
    ]);
    expect(nums('  \n'), isEmpty);
  });

  test('a hyphen is a shared cut, not a range; split cuts stay as typed', () {
    expect(nums('C012-014, C012A, C012B'), ['C012-014', 'C012A', 'C012B']);
  });

  test('unreadable ranges are reported, the rest still parse', () {
    final p = parseCutNumbers('C1~C3, C9~C5, A1~B3, C1~C2~C3, C1~C5000, C7');
    expect(p.numbers, ['C1', 'C2', 'C3', 'C7']);
    expect(p.errors, ['C9~C5', 'A1~B3', 'C1~C2~C3', 'C1~C5000']);
    expect(p.ok, isFalse);
  });

  group('formatCutNumbers', () {
    test('runs of three or more become ranges', () {
      expect(formatCutNumbers(['C100', 'C101', 'C102', 'C103']), 'C100~C103');
      expect(
        formatCutNumbers(['C100', 'C101', 'C102', 'C103', 'C105']),
        'C100~C103, C105',
      );
      expect(formatCutNumbers(['C100', 'C101']), 'C100, C101');
      expect(formatCutNumbers([]), '');
    });

    test('padding, prefixes and odd numbers break runs', () {
      expect(formatCutNumbers(['C098', 'C099', 'C100']), 'C098~C100');
      expect(formatCutNumbers(['C9', 'C10', 'C11']), 'C9, C10, C11');
      expect(formatCutNumbers(['A1', 'A2', 'B3']), 'A1, A2, B3');
      expect(
        formatCutNumbers(['C012-014', 'C015', 'C016', 'C017', 'C017A']),
        'C012-014, C015~C017, C017A',
      );
    });

    test('round trip: parsing the label gives the numbers back', () {
      for (final numbers in [
        ['C100', 'C101', 'C102', 'C103', 'C105'],
        ['C098', 'C099', 'C100', 'C101'],
        ['C012-014', 'C015', 'C016', 'C017', 'C017A', 'X'],
        ['1', '2', '3', '10', '11', '12', '13'],
      ]) {
        expect(parseCutNumbers(formatCutNumbers(numbers)).numbers, numbers);
      }
    });
  });
}
