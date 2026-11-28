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

  test('a damaged file gives the defaults', () {
    File('${tmp.path}/device.json').writeAsStringSync('{nope');
    final s = loadDeviceSettings(tmp.path);
    expect(s.themeMode, ThemeChoice.system);
    expect(s.language, LanguageChoice.device);
  });
}
