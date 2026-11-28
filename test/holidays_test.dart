import 'package:anisched/src/models/holidays.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> listed(HolidayCountry c, int year) => [
  for (final h in holidaysOf(c, year))
    '${h.date.month}/${h.date.day} ${h.name}',
];

void main() {
  test('Japan 2026, whole year (振替 5/6, 国民の休日 9/22)', () {
    expect(listed(HolidayCountry.japan, 2026), [
      '1/1 元日',
      '1/12 成人の日',
      '2/11 建国記念の日',
      '2/23 天皇誕生日',
      '3/20 春分の日',
      '4/29 昭和の日',
      '5/3 憲法記念日',
      '5/4 みどりの日',
      '5/5 こどもの日',
      '5/6 振替休日',
      '7/20 海の日',
      '8/11 山の日',
      '9/21 敬老の日',
      '9/22 国民の休日',
      '9/23 秋分の日',
      '10/12 スポーツの日',
      '11/3 文化の日',
      '11/23 勤労感謝の日',
    ]);
  });

  test('Japan: a Sunday holiday moves to Monday; the Olympic years', () {
    expect(listed(HolidayCountry.japan, 2025), contains('11/24 振替休日'));
    expect(listed(HolidayCountry.japan, 2021), contains('7/23 スポーツの日'));
    expect(listed(HolidayCountry.japan, 2019), contains('5/1 天皇の即位の日'));
  });

  test('Korea: 설날 three days; 대체공휴일 by the law\'s years', () {
    expect(listed(HolidayCountry.korea, 2026).where((h) => h.contains('설날')), [
      '2/16 설날',
      '2/17 설날',
      '2/18 설날',
    ]);
    // 3·1절 on a Saturday, 어린이날 with 부처님오신날, 추석 over a Sunday.
    expect(listed(HolidayCountry.korea, 2025).where((h) => h.contains('대체')), [
      '3/3 대체공휴일',
      '5/6 대체공휴일',
      '10/8 대체공휴일',
    ]);
    // 개천절 inside 추석: one substitute, not two.
    expect(listed(HolidayCountry.korea, 2028).where((h) => h.contains('대체')), [
      '10/5 대체공휴일',
    ]);
    // Past the lunar table only the solar holidays are known.
    expect(
      listed(HolidayCountry.korea, 2045).any((h) => h.contains('설날')),
      isFalse,
    );
  });

  test('France: Easter Monday, Ascension, Whit Monday', () {
    expect(easterSunday(2026), DateTime.utc(2026, 4, 5));
    expect(
      listed(HolidayCountry.france, 2026),
      containsAll([
        '4/6 Lundi de Pâques',
        '5/14 Ascension',
        '5/25 Lundi de Pentecôte',
      ]),
    );
  });

  test('China: holidays only; 春节 four days and 劳动节 two from 2025', () {
    final cn = listed(HolidayCountry.china, 2025);
    expect(cn.where((h) => h.contains('春节')), [
      '1/28 春节',
      '1/29 春节',
      '1/30 春节',
      '1/31 春节',
    ]);
    expect(cn.where((h) => h.contains('劳动节')), ['5/1 劳动节', '5/2 劳动节']);
    expect(listed(HolidayCountry.none, 2025), isEmpty);
  });

  test('resting on holidays takes them out of the pace, one rule for all', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    // Mon 2026-09-21 morning; the part is due Wed 9/23. 9/21–9/23 are all
    // Japanese holidays.
    final store = CatalogueStore(db, clock: () => DateTime(2026, 9, 21, 9));
    final w = store.createWork('W');
    final ep = store.addEpisode(w, '#1');
    final part = store.addPart(ep, 'A');
    final lo = store.stages(w).firstWhere((s) => s.name == 'LO').id;
    store
      ..addCut(ep, 'C1', partId: part)
      ..setPartDue(part, lo, DateTime(2026, 9, 24, 23, 59))
      ..addTasksForPart(part, lo);
    int days() => store.paceOf(store.partGroups().single)!.workDays;
    expect(store.settings.holidayCountry, HolidayCountry.japan);
    expect(store.settings.showHolidays, isTrue);
    expect(store.settings.restOnHolidays, isFalse);
    expect(days(), 4); // Mon–Thu
    store.settings.restOnHolidays = true;
    expect(days(), 1); // Thu only
    store.settings.holidayCountry = HolidayCountry.france;
    expect(days(), 4);
    expect(
      store
          .holidays(from: DateTime(2026, 7), to: DateTime(2026, 8))
          .single
          .name,
      'Fête nationale',
    );
  });
}
