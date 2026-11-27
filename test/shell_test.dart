import 'package:anisched/src/ui/app.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const AnischedApp());
}

AppView currentView(WidgetTester tester) =>
    AppView.values[tester
        .widget<IndexedStack>(find.byType(IndexedStack))
        .index!];

void main() {
  const devices = {
    'desktop': Size(1440, 900),
    'tablet landscape': Size(1280, 800),
    'tablet portrait': Size(800, 1280),
    'phone landscape': Size(915, 412),
  };

  devices.forEach((name, size) {
    testWidgets('$name puts the view switcher in the top bar', (t) async {
      await pumpAt(t, size);
      expect(find.byKey(const Key('view-switch-top')), findsOneWidget);
      expect(find.byKey(const Key('view-switch-bottom')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('phone portrait puts the view switcher at the bottom', (t) async {
    await pumpAt(t, const Size(412, 915));
    expect(find.byKey(const Key('view-switch-bottom')), findsOneWidget);
    expect(find.byKey(const Key('view-switch-top')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a view button switches the view', (t) async {
    await pumpAt(t, const Size(1280, 800));
    expect(currentView(t), AppView.list);
    for (final v in AppView.values.reversed) {
      await t.tap(find.byKey(Key('view-tab-${v.name}')));
      await t.pump();
      expect(currentView(t), v);
    }
  });

  testWidgets('the chosen view survives a rotation', (t) async {
    await pumpAt(t, const Size(1280, 800));
    await t.tap(find.byKey(const Key('view-tab-timeline')));
    await t.pump();
    t.view.physicalSize = const Size(412, 915);
    await t.pump();
    expect(find.byKey(const Key('view-switch-bottom')), findsOneWidget);
    expect(currentView(t), AppView.timeline);
  });
}
