import 'package:anisched/src/models/number_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const c3 = (prefix: 'C', digits: 3);

  test('typed numbers are stored as values; other names as typed', () {
    expect(storedNumber('C012A', c3), '12A');
    expect(storedNumber(' c12b ', c3), '12B');
    expect(storedNumber('012', c3), '12');
    expect(storedNumber('C000', c3), '0');
    expect(storedNumber('BANK1', c3), 'BANK1');
    expect(storedNumber('C012-014', c3), 'C012-014');
    expect(storedNumber('C', c3), 'C');
    expect(storedNumber('E', (prefix: 'EP', digits: 2)), 'E'); // shorter
    expect(storedNumber('C1234567890', c3), 'C1234567890'); // too long
    expect(storedNumber('C12', (prefix: '', digits: 3)), 'C12');
  });

  test('stored values show in the style; typed names stay', () {
    expect(shownNumber('12A', c3), 'C012A');
    expect(shownNumber('1234', c3), 'C1234'); // wider than the padding
    expect(shownNumber('7', (prefix: '#', digits: 2)), '#07');
    expect(shownNumber('BANK1', c3), 'BANK1');
    expect(shownNumber('012', c3), '012'); // not a stored value
    for (final typed in ['C001', 'C012A', 'C100', 'BANK1']) {
      expect(shownNumber(storedNumber(typed, c3), c3), typed);
    }
  });
}
