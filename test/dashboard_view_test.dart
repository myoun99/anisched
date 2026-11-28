import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/format.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpDash(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: AppView.dashboard,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  await t.pump();
  return store;
}

String textIn(WidgetTester t, String key) => t
    .widgetList<RichText>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(RichText)),
    )
    .map((w) => w.text.toPlainText())
    .join(' ');

void main() {
  testWidgets('the dashboard is the first tab, an icon', (t) async {
    await pumpDash(t, const Size(390, 844));
    final tabs = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('view-tab-'),
    );
    final first = tabs.evaluate().first.widget.key! as ValueKey<String>;
    expect(first.value, 'view-tab-dashboard');
    expect(
      find.descendant(
        of: find.byKey(const Key('view-tab-dashboard')),
        matching: find.byIcon(Icons.dashboard_outlined),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('today\'s numbers and the cards due, as read ($size)', (
      t,
    ) async {
      final store = await pumpDash(t, size);
      final d = store.dashboard();
      expect(textIn(t, 'dash-handed'), contains('${d.cutsHandedToday}'));
      expect(textIn(t, 'dash-worked'), contains(formatWorked(d.workedToday)));
      for (final due in d.dueSoon) {
        expect(find.byKey(Key('dash-due-${due.group.key}')), findsOneWidget);
      }
      expect(find.byKey(const Key('dash-week')), findsOneWidget);
      // A group with nothing in it does not show.
      final calm = d.late == 0 && d.retakeCuts == 0 && d.waiting == 0;
      expect(
        find.byKey(const Key('dash-attention')),
        calm ? findsNothing : findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a due card opens on the list', (t) async {
    final store = await pumpDash(t, const Size(1280, 800));
    final due = store.dashboard().dueSoon.first;
    await t.tap(find.byKey(Key('dash-due-${due.group.key}')));
    await t.pump();
    await t.pump();
    expect(find.byKey(Key('fold-cuts-${due.group.key}')), findsOneWidget);
  });
}
