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

/// Actions a key combination can run, by id — the keys of
/// [DeviceSettings.shortcuts]. More join this list as they get shortcuts.
abstract final class ShortcutAction {
  static const undo = 'undo';
  static const redo = 'redo';
}

/// The default key combinations: `Ctrl`/`Cmd`, `Shift`, `Alt` and a key,
/// joined by `+`. Apple devices ([apple]) use `Cmd`.
Map<String, List<String>> defaultShortcuts({required bool apple}) => apple
    ? const {
        ShortcutAction.undo: ['Cmd+Z'],
        ShortcutAction.redo: ['Cmd+Shift+Z'],
      }
    : const {
        ShortcutAction.undo: ['Ctrl+Z'],
        ShortcutAction.redo: ['Ctrl+Shift+Z', 'Ctrl+Y'],
      };

/// Preferences of THIS device — kept on the device, never in the
/// document, so opening the document elsewhere does not change how that
/// device looks (docs/storage.md). Work rules (rounding, day start, rest
/// days, lanes, week start) stay in the document's `settings` table.
///
/// A small JSON text, read once and written whole on every change: a file
/// in the app container on devices ([loadDeviceSettings] in
/// `device_settings_io.dart`), the browser's localStorage on the web.
class DeviceSettings {
  DeviceSettings._(
    this._write,
    this._theme,
    this._language,
    this._monthView,
    this._shortcuts,
  );

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
      m['monthView'] == true,
      {
        if (m['shortcuts'] case final Map<Object?, Object?> keys)
          for (final MapEntry(:key, :value) in keys.entries)
            if (key is String && value is List)
              key: [for (final v in value) if (v is String) v],
      },
    );
  }

  final void Function(String json) _write;
  ThemeChoice _theme;
  LanguageChoice _language;
  bool _monthView;
  final Map<String, List<String>> _shortcuts;

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

  /// The calendar shows a month rather than its usual view. Default: off.
  bool get monthView => _monthView;

  set monthView(bool on) {
    _monthView = on;
    _save();
  }

  /// Key combinations per action ([ShortcutAction]): this device's
  /// choices over [defaultShortcuts]. An empty list turns an action's
  /// keys off.
  Map<String, List<String>> shortcuts({required bool apple}) => {
    ...defaultShortcuts(apple: apple),
    ..._shortcuts,
  };

  /// Sets [action]'s key combinations; null goes back to the default.
  void setShortcut(String action, List<String>? keys) {
    if (keys == null) {
      _shortcuts.remove(action);
    } else {
      _shortcuts[action] = List.unmodifiable(keys);
    }
    _save();
  }

  void _save() => _write(
    jsonEncode({
      'themeMode': _theme.name,
      if (_language.tag != null) 'language': _language.tag,
      if (_monthView) 'monthView': true,
      if (_shortcuts.isNotEmpty) 'shortcuts': _shortcuts,
    }),
  );
}
