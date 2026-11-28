import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  // The lane rules themselves (pins move, the last stays): lanes_test.
  testWidgets('the work header adds a lane; a long press names one', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = sampleCatalogue(now);
    final lanes = store.settings.parallelLanes;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.work,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    await t.tap(find.byKey(const Key('lane-add')));
    await t.pump();
    await t.pump();
    expect(store.settings.parallelLanes, lanes + 1);
    await t.longPress(find.byKey(const Key('lane-label-0')));
    await t.pump();
    await t.enterText(find.byKey(const Key('lane-name')), '原画');
    await t.tap(find.byKey(const Key('lane-ok')));
    await t.pump();
    await t.pump();
    expect(find.text('原画'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
