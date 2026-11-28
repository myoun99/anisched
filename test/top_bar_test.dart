import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  for (final size in const [
    Size(390, 844),
    Size(844, 390),
    Size(800, 1280),
    Size(1280, 800),
  ]) {
    testWidgets('the picked-task tools end at the right margin ($size)', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = sampleCatalogue(now);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            reader: SyncCatalogueReader(store),
            store: store,
            clock: () => now,
          ),
        ),
      );
      await t.pump();
      await t.longPress(
        find.byWidgetPredicate((w) => '${w.key}'.startsWith("[<'line-")).first,
      );
      await t.pump();
      // The bar's side padding is 14: ✕ sits against it.
      expect(
        t.getTopRight(find.byKey(const Key('pick-clear'))).dx,
        size.width - 14,
      );
      // The count and actions run leftwards from there, past the app name.
      final name = t.getTopRight(find.text('Anisched'));
      expect(
        t.getTopLeft(find.byKey(const Key('top-tools'))).dx,
        greaterThan(name.dx),
      );
    });
  }
}
