import 'dart:convert';

import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  for (final n in [0, 2]) {
    testWidgets('settings warn of $n number clashes left by v20', (t) async {
      t.view.physicalSize = const Size(1440, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = sampleCatalogue(now);
      if (n > 0) {
        store.db.execute(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?);',
          [
            'number_clashes',
            jsonEncode([
              for (var i = 0; i < n; i++)
                {'kind': 'cut', 'id': i + 1, 'number': 'C01$i', 'value': '1$i'},
            ]),
          ],
        );
      }
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            initialView: AppView.settings,
            reader: SyncCatalogueReader(store),
            store: store,
            clock: () => now,
          ),
        ),
      );
      await t.pump();
      final icon = find.byKey(const Key('number-clashes'));
      if (n == 0) {
        expect(icon, findsNothing);
      } else {
        expect(t.widget<Tooltip>(icon).message, contains('$n'));
      }
    });
  }
}
