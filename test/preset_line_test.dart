import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpShell(WidgetTester t, CatalogueStore store) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: AppView.register,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return store;
}

Future<void> openClients(WidgetTester t) async {
  await t.tap(find.byKey(const Key('pick-client')));
  await t.pumpAndSettle();
}

int clientId(CatalogueStore s, String name) =>
    s.clients().firstWhere((c) => c.name == name).id;

void main() {
  testWidgets('a client renamed in its line shows on the cards', (t) async {
    final store = await pumpShell(t, sampleCatalogue(now));
    final id = clientId(store, '애니웍스');
    await openClients(t);
    await t.tap(find.byKey(Key('preset-rename-$id')));
    await t.pump();
    await t.enterText(find.byKey(Key('preset-name-$id')), '애니웍스 2');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(store.clients().any((c) => c.name == '애니웍스 2'), isTrue);
    // Closed, the list's view shows the new name on its cards.
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('view-tab-list')));
    await t.pump();
    expect(find.text('애니웍스 2'), findsWidgets);
  });

  testWidgets('a used client cannot be deleted; an unused one can', (
    t,
  ) async {
    final store = sampleCatalogue(now);
    final spare = store.addClient('빈 회사');
    await pumpShell(t, store);
    final used = clientId(store, '애니웍스');
    await openClients(t);
    IconButton delete(int id) => t.widget<IconButton>(
      find.byKey(Key('preset-delete-$id')),
    );
    expect(delete(used).onPressed, isNull, reason: 'in use: greyed');
    expect(find.byTooltip('사용 중'), findsWidgets);
    expect(delete(spare).onPressed, isNotNull);
    await t.tap(find.byKey(Key('preset-delete-$spare')));
    await t.pumpAndSettle();
    expect(store.clients().any((c) => c.id == spare), isFalse);
    expect(find.byKey(Key('preset-delete-$spare')), findsNothing);
    expect(find.byKey(const Key('preset-deleted')), findsOneWidget);
  });
}
