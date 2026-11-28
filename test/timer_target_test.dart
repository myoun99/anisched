import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<void> pumpApp(WidgetTester t, CatalogueStore store) async {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        key: UniqueKey(),
        reader: SyncCatalogueReader(store),
        store: store,
        timer: WorkTimerStore(store.db, clock: () => now),
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

String cutOnBar(WidgetTester t) {
  final slot = find.byKey(const Key('timer-cut'));
  final texts = find.descendant(of: slot, matching: find.byType(RichText));
  return t.widget<RichText>(texts.first).text.toPlainText();
}

void main() {
  testWidgets('an empty time bar picks its cut; the next start has it', (
    t,
  ) async {
    final store = sampleCatalogue(now);
    await pumpApp(t, store);
    expect(cutOnBar(t), '—');
    await t.tap(find.byKey(const Key('timer-cut')));
    await t.pumpAndSettle();
    // The catalogue, walked down by its first line at each level.
    while (find.byKey(const Key('browser')).evaluate().isNotEmpty) {
      await t.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('browse-'),
            )
            .first,
      );
      await t.pumpAndSettle();
    }
    final picked = cutOnBar(t);
    expect(picked, isNot('—'));
    final id = await SyncCatalogueReader(store).timerTarget();
    expect(id, isNotNull);
    // Not started by itself.
    expect(WorkTimerStore(store.db, clock: () => now).running(), isNull);

    // A new start of the app: the same cut, paused.
    await pumpApp(t, store);
    expect(cutOnBar(t), picked);
    expect(WorkTimerStore(store.db, clock: () => now).running(), isNull);
  });
}
