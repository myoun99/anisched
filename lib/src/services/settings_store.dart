import 'package:sqlite3/sqlite3.dart';

import '../models/catalogue.dart';
import '../models/progress.dart';

/// User settings, one row per key in the `settings` table. Missing keys
/// read as their defaults.
class SettingsStore {
  SettingsStore(this.db);

  final Database db;

  static const _secondsRounding = 'seconds_rounding';
  static const _dayStartMinutes = 'day_start_minutes';
  static const _restWeekdays = 'rest_weekdays';
  static const _paceEnd = 'pace_end';
  static const _recentPaceDays = 'recent_pace_days';
  static const _weekStart = 'week_start';
  static const _parallelLanes = 'parallel_lanes';

  /// How per-second rates round a cut's length. Default: nearest second.
  SecondsRounding get secondsRounding {
    final v = _get(_secondsRounding);
    return v == null ? SecondsRounding.nearest : SecondsRounding.fromDb(v);
  }

  set secondsRounding(SecondsRounding r) => _set(_secondsRounding, r.dbName);

  /// Minutes after midnight when a working day starts. Default: 0.
  int get dayStartMinutes => int.tryParse(_get(_dayStartMinutes) ?? '') ?? 0;

  set dayStartMinutes(int minutes) {
    RangeError.checkValueInInterval(minutes, 0, 24 * 60 - 1, 'minutes');
    _set(_dayStartMinutes, '$minutes');
  }

  /// Weekdays not worked (1 = Monday … 7 = Sunday), skipped when
  /// counting days left. Default: Saturday and Sunday. An empty set is
  /// stored as such and means "every day is a working day".
  Set<int> get restWeekdays {
    final v = _get(_restWeekdays);
    if (v == null) return {DateTime.saturday, DateTime.sunday};
    return {
      for (final p in v.split(','))
        if (int.tryParse(p) case final d? when d >= 1 && d <= 7) d,
    };
  }

  set restWeekdays(Set<int> days) {
    for (final d in days) {
      RangeError.checkValueInInterval(d, 1, 7, 'weekday');
    }
    _set(_restWeekdays, (days.toList()..sort()).join(','));
  }

  /// Which end the cuts-per-day pace counts to. Default: the plan's end,
  /// falling back to the deadline.
  PaceEnd get paceEnd {
    final v = _get(_paceEnd);
    return v == null ? PaceEnd.plan : PaceEnd.fromDb(v);
  }

  set paceEnd(PaceEnd end) => _set(_paceEnd, end.dbName);

  /// How many days back the "recent" average speed looks. Default: 28.
  int get recentPaceDays => int.tryParse(_get(_recentPaceDays) ?? '') ?? 28;

  set recentPaceDays(int days) {
    RangeError.checkValueInInterval(days, 1, 366, 'days');
    _set(_recentPaceDays, '$days');
  }

  /// The weekday a week starts on (1 = Monday … 7 = Sunday). Default:
  /// Monday.
  int get weekStart => int.tryParse(_get(_weekStart) ?? '') ?? DateTime.monday;

  set weekStart(int weekday) {
    RangeError.checkValueInInterval(weekday, 1, 7, 'weekday');
    _set(_weekStart, '$weekday');
  }

  /// How many units the user works on in parallel — the calendar's lane
  /// count. Default: 3 (provisional, pending the user's choice).
  int get parallelLanes => int.tryParse(_get(_parallelLanes) ?? '') ?? 3;

  set parallelLanes(int lanes) {
    RangeError.checkValueInInterval(lanes, 1, 20, 'lanes');
    _set(_parallelLanes, '$lanes');
  }

  String? _get(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?;', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void _set(String key, String value) => db.execute(
    'INSERT INTO settings (key, value) VALUES (?, ?) '
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value;',
    [key, value],
  );
}
