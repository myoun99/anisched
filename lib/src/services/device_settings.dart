import 'dart:convert';

export 'device_settings_io.dart'
    if (dart.library.js_interop) 'device_settings_web.dart';

/// Light or dark, or whatever the system says.
enum ThemeChoice {
  system,
  light,
  dark;

  static ThemeChoice parse(Object? v) =>
      values.where((e) => e.name == v).firstOrNull ?? system;
}

/// The UI language: the device's, or one the app ships.
enum LanguageChoice {
  device(null),
  en('en'),
  ja('ja'),
  ko('ko'),
  fr('fr'),
  zhHans('zh-Hans');

  const LanguageChoice(this.tag);

  /// BCP 47 tag; null = follow the device.
  final String? tag;

  static LanguageChoice parse(Object? v) =>
      values.where((e) => e.tag != null && e.tag == v).firstOrNull ?? device;
}

/// Preferences of THIS device — kept on the device, never in the
/// document, so opening the document elsewhere does not change how that
/// device looks (docs/storage.md). Work rules (rounding, day start, rest
/// days, lanes, week start) stay in the document's `settings` table.
///
/// A small JSON text, read once and written whole on every change: a file
/// in the app container on devices ([loadDeviceSettings] in
/// `device_settings_io.dart`), the browser's localStorage on the web.
class DeviceSettings {
  DeviceSettings._(this._write, this._theme, this._language);

  /// Settings read from [json] (null, unreadable or partial gives the
  /// defaults) that hand their JSON to [write] on every change.
  factory DeviceSettings.fromJson(String? json, void Function(String) write) {
    Object? map;
    try {
      map = json == null ? null : jsonDecode(json);
    } on FormatException {
      map = null;
    }
    final m = map is Map ? map : const {};
    return DeviceSettings._(
      write,
      ThemeChoice.parse(m['themeMode']),
      LanguageChoice.parse(m['language']),
    );
  }

  final void Function(String json) _write;
  ThemeChoice _theme;
  LanguageChoice _language;

  /// Default: [ThemeChoice.system].
  ThemeChoice get themeMode => _theme;

  set themeMode(ThemeChoice v) {
    _theme = v;
    _save();
  }

  /// Default: [LanguageChoice.device].
  LanguageChoice get language => _language;

  set language(LanguageChoice v) {
    _language = v;
    _save();
  }

  void _save() => _write(
    jsonEncode({
      'themeMode': _theme.name,
      if (_language.tag != null) 'language': _language.tag,
    }),
  );
}
