import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  // A shared (겸용) pair is one cut on the card: one chip, picked whole.
  testWidgets('a shared pair is one chip; picking it takes both tasks', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Folds.cutsInDetails.value = true;
    addTearDown(() => Folds.cutsInDetails.value = false);
    final store = sampleCatalogue(now);
    final g = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.part && g.tasks.length >= 3,
    );
    final [a, b, ...] = g.tasks;
    store.linkSharedCuts([a.cutId!, b.cutId!]);
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
    await t.tap(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
    final one = find.byKey(Key('cut-${a.id}'));
    expect(one, findsOneWidget);
    expect(find.byKey(Key('cut-${b.id}')), findsNothing, reason: 'one chip');
    expect(
      find.descendant(of: one, matching: find.textContaining('/')),
      findsOneWidget,
      reason: 'both numbers on it',
    );
    await t.ensureVisible(one);
    await t.longPress(one);
    await t.pump();
    expect(
      t.widget<Text>(find.byKey(const Key('picked-count'))).data,
      contains('2'),
    );
  });
}
