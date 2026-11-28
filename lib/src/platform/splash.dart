import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The desktop start screen's channel: the runner shows the mark until
/// the app's first frame. Windows and Linux close it on that frame by
/// themselves; macOS waits for this call.
const MethodChannel splashChannel = MethodChannel('anisched/splash');

/// Tells the runner the first frame is up. Nothing to close elsewhere.
Future<void> closeSplash() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
  try {
    await splashChannel.invokeMethod<void>('close');
  } on MissingPluginException {
    // A runner without a start screen (tests, older builds).
  }
}
