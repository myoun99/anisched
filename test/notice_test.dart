import 'package:anisched/src/ui/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpButton(WidgetTester t, void Function(BuildContext) show) =>
    t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final undo in [false, true]) {
    testWidgets('a notice goes by itself (action: $undo)', (t) async {
      var undone = 0;
      await pumpButton(
        t,
        (context) => showNotice(
          context,
          'done',
          key: const Key('n'),
          action: undo
              ? (label: 'undo', onPressed: () => undone++, key: null)
              : null,
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('n')), findsOneWidget);
      if (undo) expect(find.text('undo'), findsOneWidget);
      await t.pump(undo ? noticeTimeWithAction : noticeTime);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('n')), findsNothing, reason: 'gone');
      expect(undone, 0);
    });
  }

  testWidgets('a new notice takes the old one\'s place', (t) async {
    var n = 0;
    await pumpButton(t, (context) => showNotice(context, 'n${n++}'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('n0'), findsNothing);
    expect(find.text('n1'), findsOneWidget);
  });
}
