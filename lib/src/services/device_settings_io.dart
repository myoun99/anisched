import 'dart:io';

import 'device_settings.dart';

/// Reads `<folder>/device.json`; a missing or unreadable file gives the
/// defaults. Every change rewrites the file whole (temp + rename).
DeviceSettings loadDeviceSettings(String folder) {
  final path = '$folder${Platform.pathSeparator}device.json';
  String? json;
  try {
    json = File(path).readAsStringSync();
  } on FileSystemException {
    json = null;
  }
  return DeviceSettings.fromJson(json, (text) {
    final temp = File('$path.tmp')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text, flush: true);
    temp.renameSync(path);
  });
}
