import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/date_span.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpAt(WidgetTester t, AppView view) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  chartView.value = const ChartView();
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: view,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return store;
}

/// Opens [g]'s details in [view]: its line, its row's name, or its bar.
Future<void> open(WidgetTester t, AppView view, PartGroup g) async {
  final finder = switch (view) {
    AppView.list => find.byKey(Key('line-${g.key}')).first,
    AppView.timeline => find.descendant(
      of: find.byKey(Key('tl-bar-${g.key}')),
      matching: find.byKey(const Key('bar-tap')),
    ),
    _ => find.descendant(
      of: find.byKey(Key('work-bar-${g.key}')),
      matching: find.byKey(const Key('bar-tap')),
    ),
  };
  await t.tap(finder);
  await t.pump();
}

void main() {
  for (final view in [AppView.list, AppView.timeline, AppView.work]) {
    testWidgets('${view.name}: the details\' dates are two spans, start left', (
      t,
    ) async {
      final store = await pumpAt(t, view);
      final g = store.partGroups().firstWhere(
        (g) =>
            g.kind == GroupKind.part &&
            g.kickoffAt != null &&
            g.dueAt != null &&
            g.dueAt!.isAfter(now),
      );
      await open(t, view, g);
      final production = find.byKey(Key('span-production-${g.key}'));
      expect(production, findsOneWidget);
      expect(t.widget(production), isA<DateSpanPill>());
      expect(find.byKey(Key('span-work-${g.key}')), findsOneWidget);
      // Start, then the deadline, in one pill, left to right.
      final start = t.getRect(find.byKey(Key('details-kickoff-${g.key}')));
      final due = t.getRect(find.byKey(Key('details-due-${g.key}')));
      expect(start.right, lessThan(due.left));
      expect((start.center.dy - due.center.dy).abs(), lessThan(2));
      // No D-n inside: the line already says it.
      expect(
        find.descendant(of: production, matching: find.textContaining('D-')),
        findsNothing,
      );
      // The schedule above the estimate, each on its own row, the pills
      // starting at one x.
      final work = find.byKey(Key('span-work-${g.key}'));
      final a = t.getRect(production);
      final b = t.getRect(work);
      expect(b.top, greaterThanOrEqualTo(a.bottom));
      expect(a.left, b.left);
      final pillA = t.getRect(find.byKey(Key('details-kickoff-${g.key}')));
      final pillB = t.getRect(find.byKey(Key('details-plan-start-${g.key}')));
      expect((pillA.left - pillB.left).abs(), lessThan(1));
    });
  }

  testWidgets('the client chip sits at the top row\'s right end', (t) async {
    final store = await pumpAt(t, AppView.work);
    final g = store.partGroups().firstWhere(
      (g) =>
          g.kind == GroupKind.part &&
          g.kickoffAt != null &&
          g.dueAt != null &&
          g.dueAt!.isAfter(now),
    );
    await open(t, AppView.work, g);
    final chip = t.getRect(find.byKey(Key('details-client-${g.key}')));
    final top = t.getRect(find.byKey(Key('holding-${g.key}')));
    final details = t.getRect(find.byKey(Key('details-${g.key}')));
    // One row with the status line, right of it, at the details' end.
    expect((chip.center.dy - top.center.dy).abs(), lessThan(4));
    expect(chip.left, greaterThan(top.left));
    expect(details.right - chip.right, lessThan(20));
    // No client among the facts below.
    final schedule = t.getRect(find.byKey(Key('span-production-${g.key}')));
    expect(chip.bottom, lessThanOrEqualTo(schedule.top));
  });
}
