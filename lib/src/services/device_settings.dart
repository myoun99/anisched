import 'dart:convert';
import 'dart:io';

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

/// Preferences of THIS device — kept in the app container, never in the
/// document, so opening the document elsewhere does not change how that
/// device looks (docs/storage.md). Work rules (rounding, day start, rest
/// days, lanes, week start) stay in the document's `settings` table.
///
/// A small JSON file, read once and rewritten whole (temp + rename) on
/// every change.
class DeviceSettings {
  DeviceSettings._(this.path, this._theme, this._language);

  /// Reads `<folder>/device.json`; a missing or unreadable file gives the
  /// defaults.
  factory DeviceSettings.load(String folder) {
    final path = '$folder${Platform.pathSeparator}device.json';
    Object? json;
    try {
      json = jsonDecode(File(path).readAsStringSync());
    } on FileSystemException {
      json = null;
    } on FormatException {
      json = null;
    }
    final map = json is Map ? json : const {};
    return DeviceSettings._(
      path,
      ThemeChoice.parse(map['themeMode']),
      LanguageChoice.parse(map['language']),
    );
  }

  final String path;
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

  void _save() {
    final temp = File('$path.tmp')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'themeMode': _theme.name,
          if (_language.tag != null) 'language': _language.tag,
        }),
        flush: true,
      );
    temp.renameSync(path);
  }
}
