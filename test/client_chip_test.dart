import 'package:anisched/src/ui/client_chip.dart';
import 'package:anisched/src/ui/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'register_view_test.dart' show pumpRegister;

void main() {
  testWidgets('a chip shows the name; compact, its first letter', (t) async {
    const tag = (name: 'Studio Kumo', color: Color(0xFF2E9E6B));
    await t.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [ClientChip(tag), ClientChip(tag, compact: true)],
        ),
      ),
    );
    expect(find.text('Studio Kumo'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.byTooltip('Studio Kumo'), findsOneWidget);
  });

  testWidgets('the register screen sets a picked client\'s colour', (t) async {
    final store = await pumpRegister(t, const Size(1440, 900));
    final id = store.addClient('스튜디오 아침');
    await t.tap(find.byKey(const Key('pick-client')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('client-color')), findsNothing);
    await t.tap(find.text('스튜디오 아침').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('client-color')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('client-color-2')));
    await t.pumpAndSettle();
    final row = store.clients().firstWhere((c) => c.id == id);
    expect(row.color, clientSwatches[2].toARGB32());
  });
}
