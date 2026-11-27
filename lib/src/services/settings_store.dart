import 'package:sqlite3/sqlite3.dart';

import '../models/catalogue.dart';

/// User settings, one row per key in the `settings` table. Missing keys
/// read as their defaults.
class SettingsStore {
  SettingsStore(this.db);

  final Database db;

  static const _secondsRounding = 'seconds_rounding';
  static const _dayStartMinutes = 'day_start_minutes';

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
