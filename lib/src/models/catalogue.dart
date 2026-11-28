/// Domain values for the work catalogue. Pure Dart — no database, no UI.
library;

/// Where a task stands. Stored as [dbName].
/// In flow order (유저 2026-11-28): received → in progress → **done** (the
/// work is finished, still in the user's hands) → **submitted** (handed to
/// production, out of the user's hands); a retake comes back after a
/// submission. Submitting work not yet done marks it done too.
enum TaskStatus {
  received('received'),
  inProgress('in_progress'),
  done('done'),
  submitted('submitted'),
  retake('retake');

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

/// The factory stage list, as first seeded into the default stage preset.
/// The user edits the preset; new works copy the preset, not this list.
/// Names follow `stage_names.dart` (「work/checker」).
const List<String> defaultStageNames = [
  '콘티',
  '콘티/감독',
  'LO',
  'LO/연출',
  'LO/작감',
  'LO/총작감',
  '원화',
  '원화/연출',
  '원화/작감',
  '원화/총작감',
  '동화',
  '동화/동검',
  '시아게',
  '시아게/셀검',
  '리테이크',
  '캐릭터디자인',
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

/// What can be archived (hidden, restorable). Archiving hides everything
/// beneath it in the views; restoring brings it back as it was.
enum ArchiveKind {
  work('works'),
  episode('episodes'),
  part('parts'),
  cut('cuts'),
  storyboard('storyboards'),
  task('tasks'),

  /// A stage of one work: hidden from pickers; its tasks stay visible.
  stage('work_stages');

  const ArchiveKind(this.table);

  /// The table holding this kind; internal to the data layer.
  final String table;
}
