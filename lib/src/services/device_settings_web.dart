import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'device_settings.dart';

/// Reads this browser's settings from localStorage (`[folder]device`, the
/// folder being a name prefix here); unavailable storage gives the
/// defaults and keeps changes for the session only.
DeviceSettings loadDeviceSettings(String folder) {
  final key = '${folder}device';
  final storage = globalContext['localStorage'] as JSObject?;
  String? json;
  try {
    json = storage?.callMethod<JSString?>('getItem'.toJS, key.toJS)?.toDart;
  } on Object {
    json = null;
  }
  return DeviceSettings.fromJson(json, (text) {
    try {
      storage?.callMethod<JSAny?>('setItem'.toJS, key.toJS, text.toJS);
    } on Object {
      // Private mode or full storage: the choice lasts for this visit.
    }
  });
}
