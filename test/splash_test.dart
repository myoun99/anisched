import 'package:anisched/src/platform/splash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (platform, asks) in const [
    (TargetPlatform.macOS, true),
    (TargetPlatform.windows, false),
    (TargetPlatform.linux, false),
    (TargetPlatform.android, false),
  ]) {
    test('the first frame closes the start screen on ${platform.name}: '
        '${asks ? 'asks the runner' : 'the runner does it'}', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(splashChannel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(splashChannel, null),
      );
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await closeSplash();
      expect(calls, asks ? ['close'] : isEmpty);
    });
  }

  test('a runner without the channel is fine', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await closeSplash();
  });
}
