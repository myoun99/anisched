import 'package:anisched/src/ui/pick_field.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the current item opens in the middle, the next right under', (
    t,
  ) async {
    PickOption<int>? picked;
    final options = [
      for (var i = 1; i <= 60; i++)
        (value: i, title: 'C${i.toString().padLeft(3, '0')}', note: null),
    ];
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showCenteredPicker<int>(
              context: context,
              title: 'cut',
              search: (_) async => options,
              current: 30,
              searchable: false,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump();
    await t.pump();
    final now = t.getRect(find.byKey(const Key('pick-current')));
    final list = t.getRect(find.byType(ListView));
    expect((now.center.dy - list.center.dy).abs(), lessThan(30));
    expect(find.text('C030'), findsOneWidget);
    final next = t.getRect(find.text('C031'));
    expect(next.top, greaterThan(now.top));
    expect(next.top - now.bottom, lessThan(30), reason: 'right under it');
    await t.tap(find.text('C031'));
    await t.pump();
    expect(picked?.value, 31);
  });
}
