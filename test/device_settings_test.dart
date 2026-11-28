import 'dart:io';

import 'package:anisched/src/services/device_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('anisched_device'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('defaults, then kept across a reload', () {
    final s = loadDeviceSettings(tmp.path);
    expect(s.themeMode, ThemeChoice.system);
    expect(s.language, LanguageChoice.device);

    s
      ..themeMode = ThemeChoice.dark
      ..language = LanguageChoice.zhHans;
    final again = loadDeviceSettings(tmp.path);
    expect(again.themeMode, ThemeChoice.dark);
    expect(again.language, LanguageChoice.zhHans);
    expect(again.language.tag, 'zh-Hans');

    again.language = LanguageChoice.device;
    expect(loadDeviceSettings(tmp.path).language, LanguageChoice.device);
  });

  test('the month view choice is kept, and off by default', () {
    final s = loadDeviceSettings(tmp.path);
    expect(s.monthView, isFalse);
    s.monthView = true;
    expect(loadDeviceSettings(tmp.path).monthView, isTrue);
    expect(loadDeviceSettings(tmp.path).themeMode, ThemeChoice.system);
  });

  test('shortcuts: platform defaults, a choice kept, back to default', () {
    final s = loadDeviceSettings(tmp.path);
    expect(s.shortcuts(apple: false)[ShortcutAction.redo], [
      'Ctrl+Shift+Z',
      'Ctrl+Y',
    ]);
    expect(s.shortcuts(apple: true)[ShortcutAction.undo], ['Cmd+Z']);

    s.setShortcut(ShortcutAction.undo, ['Alt+Backspace']);
    final again = loadDeviceSettings(tmp.path);
    expect(again.shortcuts(apple: true)[ShortcutAction.undo], [
      'Alt+Backspace',
    ]);
    expect(again.shortcuts(apple: true)[ShortcutAction.redo], [
      'Cmd+Shift+Z',
    ]);

    again.setShortcut(ShortcutAction.undo, null);
    expect(loadDeviceSettings(tmp.path).shortcuts(apple: false), {
      ShortcutAction.undo: ['Ctrl+Z'],
      ShortcutAction.redo: ['Ctrl+Shift+Z', 'Ctrl+Y'],
    });
  });

  test('a damaged file gives the defaults', () {
    File('${tmp.path}/device.json').writeAsStringSync('{nope');
    final s = loadDeviceSettings(tmp.path);
    expect(s.themeMode, ThemeChoice.system);
    expect(s.language, LanguageChoice.device);
  });
}
