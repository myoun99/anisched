import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  for (final size in const [Size(1440, 900), Size(412, 915), Size(915, 412)]) {
    testWidgets('settings write through and lay out at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = sampleCatalogue(now);
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
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('rest-3')));
      await t.pump();
      expect(store.settings.restWeekdays, {3, 6, 7});
      await t.tap(find.byKey(const Key('lanes-3')));
      await t.pump();
      expect(store.settings.parallelLanes, 3);
    });
  }
}
