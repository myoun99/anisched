import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

const r = TaskStatus.received;
const w = TaskStatus.inProgress;
const s = TaskStatus.submitted;
const t = TaskStatus.retake;
const d = TaskStatus.done;

void main() {
  group('dueLabel', () {
    final now = DateTime(2026, 11, 27, 15);
    DateTime on(int day) => DateTime(2026, 11, day, 23, 59);

    test('counts whole local days', () {
      expect(dueLabel(on(30), now, w).text, 'D-3');
      expect(dueLabel(on(27), now, w).text, 'D-day');
      expect(dueLabel(on(25), now, w).text, '+2');
    });

    test('open work turns urgent near and past the deadline', () {
      expect(dueLabel(on(30), now, w).tone, DueTone.quiet);
      expect(dueLabel(on(29), now, w).tone, DueTone.soon);
      expect(dueLabel(on(27), now, r).tone, DueTone.late);
      expect(dueLabel(on(25), now, t).tone, DueTone.late);
    });

    test('handed-over work never looks urgent', () {
      expect(dueLabel(on(25), now, s).tone, DueTone.quiet);
      expect(dueLabel(on(25), now, d), (text: '—', tone: DueTone.none));
      expect(dueLabel(null, now, w).text, '—');
    });

    test('a late day start keeps the small hours on the previous day', () {
      final late = DateTime(2026, 11, 28, 2);
      expect(dueLabel(on(27), late, w).text, '+1');
      expect(dueLabel(on(27), late, w, dayStartMinutes: 4 * 60).text, 'D-day');
    });
  });

  test('formatLength writes seconds+frames at 24 fps', () {
    expect(formatLength(3500), '3+12');
    expect(formatLength(2000), '2+00');
    expect(formatLength(750), '0+18');
    expect(formatLength(null), '—');
  });

  test('formatMoney uses the currency sign and separators', () {
    expect(formatMoney('JPY', 4500), '¥4,500');
    expect(formatMoney('KRW', 900000), '₩900,000');
    expect(formatMoney('JPY', 0), '¥0');
    expect(formatMoney('EUR', 1234567), 'EUR 1,234,567');
  });

  test('totals keep currencies apart', () {
    final groups = sampleCatalogue(DateTime(2026, 11, 27)).partGroups();
    final totals = totalsByCurrency(groups);
    expect(totals.keys, ['JPY', 'KRW']);
    expect(totals['KRW'], 900000);
  });

  test('a storyboard reads as one item, a part by its label', () {
    final groups = sampleCatalogue(DateTime(2026, 11, 27)).partGroups();
    final conte = groups.firstWhere((g) => g.kind == GroupKind.storyboard);
    expect(groupTitle(conte), '콘티');
    expect(groupCount(conte), '1건');
    final part = groups.firstWhere((g) => g.kind == GroupKind.part);
    expect(groupTitle(part), endsWith('파트'));
  });
}
