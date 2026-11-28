import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../models/catalogue.dart';
import '../models/holidays.dart';
import '../models/number_style.dart';
import '../models/progress.dart';

/// User settings, one row per key in the `settings` table. Missing keys
/// read as their defaults.
class SettingsStore {
  SettingsStore(this.db);

  final CommonDatabase db;

  static const _secondsRounding = 'seconds_rounding';
  static const _dayStartMinutes = 'day_start_minutes';
  static const _restWeekdays = 'rest_weekdays';
  static const _paceEnd = 'pace_end';
  static const _recentPaceDays = 'recent_pace_days';
  static const _weekStart = 'week_start';
  static const _parallelLanes = 'parallel_lanes';
  static const _laneNames = 'lane_names';
  static const _timerAutoStart = 'timer_auto_start';
  static const _timerTarget = 'timer_target';
  static const _cutStyle = 'cut_style';
  static const _holidayCountry = 'holiday_country';
  static const _showHolidays = 'show_holidays';
  static const _restOnHolidays = 'rest_on_holidays';
  static const _episodeStyle = 'episode_style';

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
  /// count. Default: 2.
  int get parallelLanes => int.tryParse(_get(_parallelLanes) ?? '') ?? 2;

  set parallelLanes(int lanes) {
    RangeError.checkValueInInterval(lanes, 1, 20, 'lanes');
    _set(_parallelLanes, '$lanes');
  }

  /// The user's names for the calendar lanes, one per lane
  /// ([parallelLanes] long). An unnamed lane is null — the view shows its
  /// number.
  List<String?> get laneNames {
    final stored = <String?>[];
    final v = _get(_laneNames);
    if (v != null) {
      for (final n in jsonDecode(v) as List<Object?>) {
        stored.add(n is String && n.isNotEmpty ? n : null);
      }
    }
    return [for (var i = 0; i < parallelLanes; i++) stored.elementAtOrNull(i)];
  }

  /// Names the lanes in order; null or empty leaves a lane unnamed. Names
  /// past the lane count are kept for when lanes are added.
  set laneNames(List<String?> names) =>
      _set(_laneNames, jsonEncode([for (final n in names) n ?? '']));

  /// "Start the timer when the cut changes": switching to another cut
  /// while the timer runs moves it to the new cut when true; false
  /// (default) pauses it. A paused timer stays paused either way.
  bool get timerAutoStart => _get(_timerAutoStart) == '1';

  set timerAutoStart(bool follow) => _set(_timerAutoStart, follow ? '1' : '0');

  /// The task the timer was last pointed at, as stored (see
  /// `CatalogueStore.timerTarget`, which drops one that is gone).
  int? get timerTargetId => int.tryParse(_get(_timerTarget) ?? '');

  set timerTargetId(int? taskId) =>
      _set(_timerTarget, taskId == null ? '' : '$taskId');

  /// Whose public holidays the calendar knows (유저 2026-11-28). Default:
  /// Japan.
  HolidayCountry get holidayCountry =>
      HolidayCountry.parse(_get(_holidayCountry));

  set holidayCountry(HolidayCountry c) => _set(_holidayCountry, c.code);

  /// Whether views mark the holidays. Default: on.
  bool get showHolidays => _get(_showHolidays) != '0';

  set showHolidays(bool on) => _set(_showHolidays, on ? '1' : '0');

  /// Whether holidays count as days off for the pace, like rest weekdays.
  /// Default: off.
  bool get restOnHolidays => _get(_restOnHolidays) == '1';

  set restOnHolidays(bool on) => _set(_restOnHolidays, on ? '1' : '0');

  /// How cut numbers are written, for the whole document. Default `C001`.
  NumberStyle get cutStyle => _style(_cutStyle) ?? defaultCutStyle;

  set cutStyle(NumberStyle s) => _setStyle(_cutStyle, s);

  /// How episode numbers are written. Default `#01`.
  NumberStyle get episodeStyle => _style(_episodeStyle) ?? defaultEpisodeStyle;

  set episodeStyle(NumberStyle s) => _setStyle(_episodeStyle, s);

  NumberStyle? _style(String key) {
    final v = _get(key);
    if (v == null) return null;
    final m = jsonDecode(v);
    if (m is! Map) return null;
    final prefix = m['prefix'];
    final digits = m['digits'];
    if (prefix is! String || digits is! int) return null;
    if (digits < minStyleDigits || digits > maxStyleDigits) return null;
    return (prefix: prefix, digits: digits);
  }

  void _setStyle(String key, NumberStyle s) {
    RangeError.checkValueInInterval(
      s.digits,
      minStyleDigits,
      maxStyleDigits,
      'digits',
    );
    _set(key, jsonEncode({'prefix': s.prefix, 'digits': s.digits}));
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
