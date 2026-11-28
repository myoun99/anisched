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
  // One place on every screen: the view switcher along the bottom, the
  // same bar as a phone's, held either way, on a tablet and a desktop.
  for (final size in const [
    Size(412, 915),
    Size(915, 412),
    Size(800, 1280),
    Size(1280, 800),
    Size(1920, 1080),
  ]) {
    testWidgets('the view switcher sits at the bottom at $size', (t) async {
      await pumpAt(t, size);
      final bar = t.getRect(find.byKey(const Key('view-switch')));
      expect(bar.bottom, greaterThan(size.height - 60));
      expect(bar.width, greaterThan(size.width - 40), reason: 'full width');
      expect(t.takeException(), isNull);
    });
  }

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
    expect(find.byKey(const Key('view-switch')), findsOneWidget);
    expect(currentView(t), AppView.timeline);
  });
}
