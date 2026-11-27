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

class Rate {
  const Rate(this.unit, this.amount);

  final RateUnit unit;

  /// Integer amount in the currency's smallest unit.
  final int amount;

  /// The pay for one unit of work, or null when a per-second rate meets a
  /// cut with no length yet. Fractions of the smallest unit round half up.
  int? payFor({int? lengthMs}) => switch (unit) {
    RateUnit.fixed => amount,
    RateUnit.perSecond =>
      lengthMs == null ? null : (amount * lengthMs + 500) ~/ 1000,
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
