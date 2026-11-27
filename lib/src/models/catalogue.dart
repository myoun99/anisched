/// Domain values for the work catalogue. Pure Dart — no database, no UI.
library;

/// Where a task stands. Stored as [dbName].
enum TaskStatus {
  received('received'),
  inProgress('in_progress'),
  submitted('submitted'),
  retake('retake'),
  done('done');

  const TaskStatus(this.dbName);

  final String dbName;

  static TaskStatus fromDb(String s) => values.firstWhere((v) => v.dbName == s);
}

/// How a rate is applied. Stored as [dbName].
enum RateUnit {
  /// One amount per unit of work (per cut, or per storyboard).
  fixed('fixed'),

  /// Amount per second of the cut's length.
  perSecond('per_second');

  const RateUnit(this.dbName);

  final String dbName;

  static RateUnit fromDb(String s) => values.firstWhere((v) => v.dbName == s);
}

/// How a cut's length is turned into whole seconds for a per-second rate.
/// A user setting; stored as [dbName].
enum SecondsRounding {
  /// No rounding: 3.5 s pays 3.5 seconds.
  exact('exact'),

  /// Any fraction counts as a full second.
  up('up'),

  /// Fractions are dropped.
  down('down'),

  /// Half a second or more counts as a full second. The default.
  nearest('nearest');

  const SecondsRounding(this.dbName);

  final String dbName;

  static SecondsRounding fromDb(String s) =>
      values.firstWhere((v) => v.dbName == s);
}

class Rate {
  const Rate(this.unit, this.amount);

  final RateUnit unit;

  /// Integer amount in the currency's smallest unit.
  final int amount;

  /// The pay for one unit of work, or null when a per-second rate meets a
  /// cut with no length yet. For per-second rates the cut *length* is
  /// rounded to whole seconds by [rounding] before multiplying; with
  /// [SecondsRounding.exact] the length is used as is and only the final
  /// amount rounds half up to the smallest currency unit.
  int? payFor({
    int? lengthMs,
    SecondsRounding rounding = SecondsRounding.nearest,
  }) => switch (unit) {
    RateUnit.fixed => amount,
    RateUnit.perSecond =>
      lengthMs == null ? null : _perSecond(lengthMs, rounding),
  };

  int _perSecond(int lengthMs, SecondsRounding rounding) => switch (rounding) {
    SecondsRounding.exact => (amount * lengthMs + 500) ~/ 1000,
    SecondsRounding.up => amount * ((lengthMs + 999) ~/ 1000),
    SecondsRounding.down => amount * (lengthMs ~/ 1000),
    SecondsRounding.nearest => amount * ((lengthMs + 500) ~/ 1000),
  };
}

/// Stages a new work starts with; the user edits them per work.
const List<String> defaultStageNames = [
  '콘티',
  '콘티 체크',
  'LO',
  'LO 연출 수정',
  'LO 작감 수정',
  'LO 총작감 수정',
  '원화',
  '원화 연출 수정',
  '원화 작감 수정',
  '원화 총작감 수정',
];

/// A key that sorts cut and episode numbers naturally: digit runs are
/// zero-padded so "C2" < "C10" < "C10A", case is ignored.
String naturalSortKey(String label) =>
    label.trim().toLowerCase().replaceAllMapped(
      RegExp(r'\d+'),
      (m) => m[0]!.replaceFirst(RegExp('^0+(?=.)'), '').padLeft(10, '0'),
    );

/// The local-date billing period that closes on [closingDay] of
/// [year]/[month], as `[start, end)`. A null closing day, or one past the
/// month's last day, closes on the last day.
({DateTime start, DateTime end}) billingPeriod(
  int year,
  int month,
  int? closingDay,
) {
  DateTime closeOf(int y, int m) {
    final last = DateTime(y, m + 1, 0).day;
    final d = closingDay == null || closingDay > last ? last : closingDay;
    return DateTime(y, m, d);
  }

  final prevClose = closeOf(year, month - 1);
  final close = closeOf(year, month);
  return (
    start: DateTime(prevClose.year, prevClose.month, prevClose.day + 1),
    end: DateTime(close.year, close.month, close.day + 1),
  );
}

/// The local `[start, end)` of the working day [date] falls on, when days
/// begin [dayStartMinutes] after midnight (0 = midnight).
({DateTime start, DateTime end}) dayRange(DateTime date, int dayStartMinutes) {
  final local = date.toLocal();
  var day = DateTime(local.year, local.month, local.day);
  if (local.isBefore(day.add(Duration(minutes: dayStartMinutes)))) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return (
    start: day.add(Duration(minutes: dayStartMinutes)),
    end: DateTime(
      day.year,
      day.month,
      day.day + 1,
    ).add(Duration(minutes: dayStartMinutes)),
  );
}
