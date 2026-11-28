import 'support/sample_catalogue.dart';

import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/client_chip.dart';
import 'package:anisched/src/ui/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'register_view_test.dart' show pumpRegister;

final now = DateTime(2026, 11, 27, 14);

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

  testWidgets('a narrow list line shows the client as its square', (t) async {
    for (final (width, compact) in const [(390.0, true), (1280.0, false)]) {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = sampleCatalogue(now);
      await t.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.light(),
          home: AppShell(
            reader: SyncCatalogueReader(store),
            store: store,
            clock: () => now,
          ),
        ),
      );
      await t.pump();
      await t.pump();
      final chips = t.widgetList<ClientChip>(find.byType(ClientChip));
      expect(chips, isNotEmpty);
      expect(
        chips.every((c) => c.compact == compact),
        isTrue,
        reason: '$width',
      );
    }
  });
}
