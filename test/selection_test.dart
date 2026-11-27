import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/selection.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  test('a group is picked whole, in part, or not at all', () {
    final groups = sampleCatalogue(now).partGroups();
    final g = groups.firstWhere((g) => g.total > 1);
    final sel = TaskSelection();
    expect(sel.of(g), Picked.none);
    sel.toggleTask(g.tasks.first);
    expect(sel.of(g), Picked.some);
    sel.toggleGroup(g);
    expect(sel.of(g), Picked.all);
    expect(sel.count, g.total);
    sel.toggleGroup(g);
    expect(sel.isEmpty, isTrue);
  });

  testWidgets('long-press picks a part; an action moves all its cuts', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = sampleCatalogue(now);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.sheet,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    final g = store.partGroups().firstWhere(
      (g) => g.workTitle == '별빛 정류장' && g.partLabel == 'C',
    );
    expect(find.text('0건'), findsOneWidget);
    await t.longPress(find.byKey(Key('line-${g.key}')));
    await t.pump();
    expect(find.text('${g.total}건'), findsOneWidget);

    await t.tap(find.byKey(const Key('apply-submitted')));
    await t.pump();
    await t.pump();
    final after = store
        .partGroups(includeDone: true)
        .firstWhere((x) => x.key == g.key);
    expect(after.tasks.every((x) => x.status == TaskStatus.submitted), isTrue);
    expect(find.text('0건'), findsOneWidget);
  });
}
