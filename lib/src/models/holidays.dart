/// Public holidays, offline (유저 2026-11-28): Japan (the default), Korea,
/// France and China. Pure Dart; names stay in each country's own language
/// (「春分の日」, 「설날」) — the UI shows them as they are.
///
/// - Japan: the rules of the national holiday law — fixed days, Happy
///   Monday, the equinox formula (checked against an astronomical
///   computation for 2000–2099), 振替休日 and 国民の休日 — plus the one-off
///   years in a table (2019 enthronement, 2020/2021 Olympics). Years from
///   2000.
/// - Korea and China: solar holidays by rule; the lunar ones (설날 · 부처님
///   오신날 · 추석, 春节 · 端午 · 中秋) and 清明 from tables for 2020–2040,
///   computed from new moons and solar terms (Meeus) in KST / CST and
///   checked against published dates. Outside those years only the solar
///   holidays are given. Korea's 대체공휴일 follow the law's years; one-off
///   temporary holidays and election days are not included. China: the
///   statutory days only, no 调休 make-up working days.
/// - France: fixed days plus Easter Monday, Ascension and Whit Monday
///   (Gregorian Easter).
library;

/// Whose holidays to use (the `holiday_country` work rule).
enum HolidayCountry {
  none('none'),
  japan('JP'),
  korea('KR'),
  france('FR'),
  china('CN');

  const HolidayCountry(this.code);

  final String code;

  static HolidayCountry parse(String? code) =>
      values.where((c) => c.code == code).firstOrNull ?? japan;
}

/// One holiday: a date (UTC midnight of that calendar day) and its name in
/// the country's language.
typedef Holiday = ({DateTime date, String name});

/// [country]'s public holidays in [year], by date.
List<Holiday> holidaysOf(HolidayCountry country, int year) {
  final list = switch (country) {
    HolidayCountry.none => <Holiday>[],
    HolidayCountry.japan => _japan(year),
    HolidayCountry.korea => _korea(year),
    HolidayCountry.france => _france(year),
    HolidayCountry.china => _china(year),
  };
  return list..sort((a, b) => a.date.compareTo(b.date));
}

/// Whether a (local) date is one of [country]'s holidays; each year is
/// worked out once.
bool Function(DateTime date) holidayTest(HolidayCountry country) {
  final byYear = <int, Set<DateTime>>{};
  return (date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    return (byYear[d.year] ??= {
      for (final h in holidaysOf(country, d.year)) h.date,
    }).contains(d);
  };
}

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

/// The [n]th Monday of [month].
DateTime _monday(int year, int month, int n) {
  final first = _d(year, month, 1);
  final offset = (DateTime.monday - first.weekday + 7) % 7;
  return first.add(Duration(days: offset + 7 * (n - 1)));
}

// ---- Japan ----

List<Holiday> _japan(int year) {
  final base = <Holiday>[];
  void add(DateTime date, String name) => base.add((date: date, name: name));
  final y = year;
  final shift = 0.242194 * (y - 1980) - ((y - 1980) ~/ 4);
  add(_d(y, 1, 1), '元日');
  add(_monday(y, 1, 2), '成人の日');
  add(_d(y, 2, 11), '建国記念の日');
  if (y >= 2020) add(_d(y, 2, 23), '天皇誕生日');
  add(_d(y, 3, (20.8431 + shift).floor()), '春分の日');
  add(_d(y, 4, 29), y >= 2007 ? '昭和の日' : 'みどりの日');
  add(_d(y, 5, 3), '憲法記念日');
  if (y >= 2007) add(_d(y, 5, 4), 'みどりの日');
  add(_d(y, 5, 5), 'こどもの日');
  final olympics = _japanOlympics[y];
  add(olympics?.sea ?? _monday(y, 7, 3), '海の日');
  if (y >= 2016) add(olympics?.mountain ?? _d(y, 8, 11), '山の日');
  add(_monday(y, 9, 3), '敬老の日');
  add(_d(y, 9, (23.2488 + shift).floor()), '秋分の日');
  add(olympics?.sports ?? _monday(y, 10, 2), y >= 2020 ? 'スポーツの日' : '体育の日');
  add(_d(y, 11, 3), '文化の日');
  add(_d(y, 11, 23), '勤労感謝の日');
  if (y <= 2018) add(_d(y, 12, 23), '天皇誕生日');
  if (y == 2019) {
    add(_d(y, 5, 1), '天皇の即位の日');
    add(_d(y, 10, 22), '即位礼正殿の儀の行われる日');
  }
  final days = {for (final h in base) h.date};
  final out = [...base];
  // 振替休日: a holiday on a Sunday moves to the next day that is not one.
  for (final h in base) {
    if (h.date.weekday != DateTime.sunday) continue;
    var next = h.date.add(const Duration(days: 1));
    while (days.contains(next)) {
      next = next.add(const Duration(days: 1));
    }
    out.add((date: next, name: '振替休日'));
    days.add(next);
  }
  // 国民の休日: a day between two holidays (祝日) becomes one too.
  final shuku = {for (final h in base) h.date};
  for (final h in base) {
    final mid = h.date.add(const Duration(days: 1));
    if (!days.contains(mid) &&
        mid.weekday != DateTime.sunday &&
        shuku.contains(mid.add(const Duration(days: 1)))) {
      out.add((date: mid, name: '国民の休日'));
      days.add(mid);
    }
  }
  return out;
}

/// The Olympic years' moved holidays (Tokyo 2020, held 2021).
final Map<int, ({DateTime sea, DateTime sports, DateTime mountain})>
_japanOlympics = {
  2020: (
    sea: _d(2020, 7, 23),
    sports: _d(2020, 7, 24),
    mountain: _d(2020, 8, 10),
  ),
  2021: (
    sea: _d(2021, 7, 22),
    sports: _d(2021, 7, 23),
    mountain: _d(2021, 8, 8),
  ),
};

// ---- Korea ----

typedef _Md = (int, int);

/// 설날 (음력 1/1), 부처님오신날 (4/8), 추석 (8/15), KST.
const Map<int, ({_Md seollal, _Md buddha, _Md chuseok})> _koreaLunar = {
  2020: (seollal: (1, 25), buddha: (4, 30), chuseok: (10, 1)),
  2021: (seollal: (2, 12), buddha: (5, 19), chuseok: (9, 21)),
  2022: (seollal: (2, 1), buddha: (5, 8), chuseok: (9, 10)),
  2023: (seollal: (1, 22), buddha: (5, 27), chuseok: (9, 29)),
  2024: (seollal: (2, 10), buddha: (5, 15), chuseok: (9, 17)),
  2025: (seollal: (1, 29), buddha: (5, 5), chuseok: (10, 6)),
  2026: (seollal: (2, 17), buddha: (5, 24), chuseok: (9, 25)),
  2027: (seollal: (2, 7), buddha: (5, 13), chuseok: (9, 15)),
  2028: (seollal: (1, 27), buddha: (5, 2), chuseok: (10, 3)),
  2029: (seollal: (2, 13), buddha: (5, 20), chuseok: (9, 22)),
  2030: (seollal: (2, 3), buddha: (5, 9), chuseok: (9, 12)),
  2031: (seollal: (1, 23), buddha: (5, 28), chuseok: (10, 1)),
  2032: (seollal: (2, 11), buddha: (5, 16), chuseok: (9, 19)),
  2033: (seollal: (1, 31), buddha: (5, 6), chuseok: (9, 8)),
  2034: (seollal: (2, 19), buddha: (5, 25), chuseok: (9, 27)),
  2035: (seollal: (2, 8), buddha: (5, 15), chuseok: (9, 16)),
  2036: (seollal: (1, 28), buddha: (5, 3), chuseok: (10, 4)),
  2037: (seollal: (2, 15), buddha: (5, 22), chuseok: (9, 24)),
  2038: (seollal: (2, 4), buddha: (5, 11), chuseok: (9, 13)),
  2039: (seollal: (1, 24), buddha: (4, 30), chuseok: (10, 2)),
  2040: (seollal: (2, 12), buddha: (5, 18), chuseok: (9, 21)),
};

List<Holiday> _korea(int year) {
  final y = year;
  final out = <Holiday>[];
  void add(DateTime date, String name) => out.add((date: date, name: name));
  final oneDay = <(DateTime, String, bool)>[]; // date, name, may be replaced
  void day(DateTime date, String name, {required bool substitute}) {
    add(date, name);
    oneDay.add((date, name, substitute));
  }

  day(_d(y, 1, 1), '신정', substitute: false);
  day(_d(y, 3, 1), '삼일절', substitute: y >= 2022);
  day(_d(y, 5, 5), '어린이날', substitute: y >= 2014);
  day(_d(y, 6, 6), '현충일', substitute: false);
  day(_d(y, 8, 15), '광복절', substitute: y >= 2021);
  day(_d(y, 10, 3), '개천절', substitute: y >= 2021);
  day(_d(y, 10, 9), '한글날', substitute: y >= 2021);
  day(_d(y, 12, 25), '기독탄신일', substitute: y >= 2023);
  final lunar = _koreaLunar[y];
  final blocks = <List<DateTime>>[];
  if (lunar != null) {
    day(
      _d(y, lunar.buddha.$1, lunar.buddha.$2),
      '부처님오신날',
      substitute: y >= 2023,
    );
    for (final (md, name) in [(lunar.seollal, '설날'), (lunar.chuseok, '추석')]) {
      final mid = _d(y, md.$1, md.$2);
      final block = [for (var i = -1; i <= 1; i++) mid.add(Duration(days: i))];
      for (final d in block) {
        add(d, name);
      }
      blocks.add(block);
    }
  }
  // 대체공휴일: one per occasion — a 설날/추석 block on a Sunday or over
  // another holiday, or an eligible single holiday on a weekend or shared
  // with another — on the next weekday that is not already a holiday.
  final taken = {for (final h in out) h.date};
  final blockDays = {for (final b in blocks) ...b};
  final singles = <DateTime, List<bool>>{};
  for (final (date, _, substitute) in oneDay) {
    (singles[date] ??= []).add(substitute);
  }
  bool weekend(DateTime d) => d.weekday >= DateTime.saturday;
  final after = <DateTime>[];
  if (y >= 2014) {
    for (final block in blocks) {
      if (block.any(
        (d) => d.weekday == DateTime.sunday || singles.containsKey(d),
      )) {
        after.add(block.last);
      }
    }
  }
  for (final MapEntry(key: date, value: flags) in singles.entries) {
    if (!flags.contains(true) || blockDays.contains(date)) continue;
    if (weekend(date) || flags.length > 1) after.add(date);
  }
  after.sort();
  for (final from in after) {
    var next = from.add(const Duration(days: 1));
    while (taken.contains(next) || weekend(next)) {
      next = next.add(const Duration(days: 1));
    }
    add(next, '대체공휴일');
    taken.add(next);
  }
  return out;
}

// ---- France ----

/// Gregorian Easter Sunday (anonymous algorithm).
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return _d(year, month, day);
}

List<Holiday> _france(int year) {
  final y = year;
  final easter = easterSunday(y);
  return [
    (date: _d(y, 1, 1), name: "Jour de l'an"),
    (date: easter.add(const Duration(days: 1)), name: 'Lundi de Pâques'),
    (date: _d(y, 5, 1), name: 'Fête du Travail'),
    (date: _d(y, 5, 8), name: 'Victoire 1945'),
    (date: easter.add(const Duration(days: 39)), name: 'Ascension'),
    (date: easter.add(const Duration(days: 50)), name: 'Lundi de Pentecôte'),
    (date: _d(y, 7, 14), name: 'Fête nationale'),
    (date: _d(y, 8, 15), name: 'Assomption'),
    (date: _d(y, 11, 1), name: 'Toussaint'),
    (date: _d(y, 11, 11), name: 'Armistice 1918'),
    (date: _d(y, 12, 25), name: 'Noël'),
  ];
}

// ---- China ----

/// 春节 (正月初一), 清明, 端午 (五月初五), 中秋 (八月十五), CST.
const Map<
  int,
  ({_Md springFestival, _Md qingming, _Md dragonBoat, _Md midAutumn})
>
_chinaLunar = {
  2020: (
    springFestival: (1, 25),
    qingming: (4, 4),
    dragonBoat: (6, 25),
    midAutumn: (10, 1),
  ),
  2021: (
    springFestival: (2, 12),
    qingming: (4, 4),
    dragonBoat: (6, 14),
    midAutumn: (9, 21),
  ),
  2022: (
    springFestival: (2, 1),
    qingming: (4, 5),
    dragonBoat: (6, 3),
    midAutumn: (9, 10),
  ),
  2023: (
    springFestival: (1, 22),
    qingming: (4, 5),
    dragonBoat: (6, 22),
    midAutumn: (9, 29),
  ),
  2024: (
    springFestival: (2, 10),
    qingming: (4, 4),
    dragonBoat: (6, 10),
    midAutumn: (9, 17),
  ),
  2025: (
    springFestival: (1, 29),
    qingming: (4, 4),
    dragonBoat: (5, 31),
    midAutumn: (10, 6),
  ),
  2026: (
    springFestival: (2, 17),
    qingming: (4, 5),
    dragonBoat: (6, 19),
    midAutumn: (9, 25),
  ),
  2027: (
    springFestival: (2, 6),
    qingming: (4, 5),
    dragonBoat: (6, 9),
    midAutumn: (9, 15),
  ),
  2028: (
    springFestival: (1, 26),
    qingming: (4, 4),
    dragonBoat: (5, 28),
    midAutumn: (10, 3),
  ),
  2029: (
    springFestival: (2, 13),
    qingming: (4, 4),
    dragonBoat: (6, 16),
    midAutumn: (9, 22),
  ),
  2030: (
    springFestival: (2, 3),
    qingming: (4, 5),
    dragonBoat: (6, 5),
    midAutumn: (9, 12),
  ),
  2031: (
    springFestival: (1, 23),
    qingming: (4, 5),
    dragonBoat: (6, 24),
    midAutumn: (10, 1),
  ),
  2032: (
    springFestival: (2, 11),
    qingming: (4, 4),
    dragonBoat: (6, 12),
    midAutumn: (9, 19),
  ),
  2033: (
    springFestival: (1, 31),
    qingming: (4, 4),
    dragonBoat: (6, 1),
    midAutumn: (9, 8),
  ),
  2034: (
    springFestival: (2, 19),
    qingming: (4, 5),
    dragonBoat: (6, 20),
    midAutumn: (9, 27),
  ),
  2035: (
    springFestival: (2, 8),
    qingming: (4, 5),
    dragonBoat: (6, 10),
    midAutumn: (9, 16),
  ),
  2036: (
    springFestival: (1, 28),
    qingming: (4, 4),
    dragonBoat: (5, 30),
    midAutumn: (10, 4),
  ),
  2037: (
    springFestival: (2, 15),
    qingming: (4, 4),
    dragonBoat: (6, 18),
    midAutumn: (9, 24),
  ),
  2038: (
    springFestival: (2, 4),
    qingming: (4, 5),
    dragonBoat: (6, 7),
    midAutumn: (9, 13),
  ),
  2039: (
    springFestival: (1, 24),
    qingming: (4, 5),
    dragonBoat: (5, 27),
    midAutumn: (10, 2),
  ),
  2040: (
    springFestival: (2, 12),
    qingming: (4, 4),
    dragonBoat: (6, 14),
    midAutumn: (9, 20),
  ),
};

List<Holiday> _china(int year) {
  final y = year;
  final out = <Holiday>[
    (date: _d(y, 1, 1), name: '元旦'),
    (date: _d(y, 5, 1), name: '劳动节'),
    if (y >= 2025) (date: _d(y, 5, 2), name: '劳动节'),
    for (var i = 1; i <= 3; i++) (date: _d(y, 10, i), name: '国庆节'),
  ];
  final lunar = _chinaLunar[y];
  if (lunar != null) {
    final spring = _d(y, lunar.springFestival.$1, lunar.springFestival.$2);
    // Since 2025: 除夕 and 初一–初三; before: 初一–初三.
    for (var i = y >= 2025 ? -1 : 0; i <= 2; i++) {
      out.add((date: spring.add(Duration(days: i)), name: '春节'));
    }
    out
      ..add((date: _d(y, lunar.qingming.$1, lunar.qingming.$2), name: '清明节'))
      ..add((
        date: _d(y, lunar.dragonBoat.$1, lunar.dragonBoat.$2),
        name: '端午节',
      ))
      ..add((date: _d(y, lunar.midAutumn.$1, lunar.midAutumn.$2), name: '中秋节'));
  }
  return out;
}
