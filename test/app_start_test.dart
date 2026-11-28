import 'dart:async';

import 'package:anisched/src/ui/app_start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the name and a spinner until ready, then the app', (t) async {
    final ready = Completer<Widget>();
    await t.pumpWidget(AppStart(load: () => ready.future));
    expect(find.byKey(const Key('app-loading')), findsOneWidget);
    expect(find.text('Anisched'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete(const MaterialApp(home: Text('shell', key: Key('the-app'))));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('app-loading')), findsNothing);
    expect(find.byKey(const Key('the-app')), findsOneWidget);
  });

  testWidgets('dark when the system is dark', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(AppStart(load: () => Completer<Widget>().future));
    final box = t.widget<ColoredBox>(find.byKey(const Key('app-loading')));
    expect(box.color.computeLuminance(), lessThan(0.1));
  });
}
