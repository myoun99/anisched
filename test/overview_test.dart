import 'package:anisched/src/controllers/overview.dart';
import 'package:anisched/src/controllers/sample_overview.dart';
import 'package:anisched/src/models/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

const r = TaskStatus.received;
const w = TaskStatus.inProgress;
const s = TaskStatus.submitted;
const t = TaskStatus.retake;
const d = TaskStatus.done;

void main() {
  group('partStatus', () {
    test('all done is done', () => expect(partStatus([d, d]), d));
    test('any retake wins', () => expect(partStatus([d, s, t, r]), t));
    test('all handed in is submitted', () => expect(partStatus([s, d]), s));
    test('all received is received', () => expect(partStatus([r, r]), r));
    test('a mix is in progress', () => expect(partStatus([r, s]), w));
    test('no tasks reads as received', () => expect(partStatus([]), r));
  });

  group('dueLabel', () {
    final today = DateTime(2026, 11, 27, 15);
    DateTime on(int day) => DateTime(2026, 11, day, 23, 59);

    test('counts whole local days', () {
      expect(dueLabel(on(30), today, w).text, 'D-3');
      expect(dueLabel(on(27), today, w).text, 'D-day');
      expect(dueLabel(on(25), today, w).text, '+2');
    });

    test('open work turns urgent near and past the deadline', () {
      expect(dueLabel(on(30), today, w).tone, DueTone.quiet);
      expect(dueLabel(on(29), today, w).tone, DueTone.soon);
      expect(dueLabel(on(27), today, r).tone, DueTone.late);
      expect(dueLabel(on(25), today, t).tone, DueTone.late);
    });

    test('handed-in work never looks urgent', () {
      expect(dueLabel(on(25), today, s).tone, DueTone.quiet);
      expect(dueLabel(on(25), today, d), (text: '—', tone: DueTone.none));
      expect(dueLabel(null, today, w).text, '—');
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

  test('the sample covers every status and keeps currencies apart', () {
    final parts = sampleOverview(DateTime(2026, 11, 27));
    final statuses = {for (final p in parts) ...p.tasks.map((t) => t.status)};
    expect(statuses, TaskStatus.values.toSet());
    expect(totalsByCurrency(parts).keys, containsAll(['JPY', 'KRW']));
    expect(parts.any((p) => p.tasks.any((t) => !t.dueFromPart)), isTrue);
  });
}
