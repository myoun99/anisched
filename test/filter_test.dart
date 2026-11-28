import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/filter.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  test('deadline windows split open work and skip handed-in work', () {
    final store = sampleCatalogue(now);
    // One unit handed in, so the default view has something to hide.
    final sent = store.partGroups().first;
    store.setStatusMany([
      for (final t in sent.tasks) t.id,
    ], TaskStatus.submitted);
    final groups = store.partGroups(includeDone: true);
    List<String> keys(ViewFilter f) => [
      for (final g in groups)
        if (f.matches(g, now, const {})) g.key,
    ];
    final open = groups.where((g) => g.status.isOpen);
    final windows = [
      DueRange.late,
      DueRange.within3,
      DueRange.within14,
      DueRange.later,
    ];
    final split = [for (final r in windows) ...keys(ViewFilter(range: r))];
    expect(split.toSet().length, split.length, reason: 'windows overlap');
    expect(split.toSet(), {
      for (final g in open)
        if (g.dueAt != null) g.key,
    });
    expect(keys(const ViewFilter()).length, lessThan(groups.length));
    expect(keys(const ViewFilter(showDone: true)).length, groups.length);
  });

  test('client and work narrow the list', () {
    final store = sampleCatalogue(now);
    final groups = store.partGroups();
    final work = groups.first.workId;
    final f = ViewFilter(workId: work);
    expect(
      groups
          .where((g) => f.matches(g, now, const {}))
          .every((g) => g.workId == work),
      isTrue,
    );
    const byClient = ViewFilter(clientId: 7);
    expect(
      groups
          .where((g) => byClient.matches(g, now, {work: 7}))
          .map((g) => g.workId),
      everyElement(work),
    );
  });

  testWidgets('dragging a grip saves the order; sorting by due clears it', (
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
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    final first = store.partGroups().first.key;
    final grip = find.byKey(Key('grip-$first'));
    expect(grip, findsOneWidget);
    await t.drag(grip, const Offset(0, 200));
    await t.pumpAndSettle();
    expect(store.hasGroupOrder, isTrue);
    expect(store.partGroups().first.key, isNot(first));

    await t.tap(find.byKey(const Key('sort-by-due')));
    await t.pump();
    await t.pump();
    expect(store.hasGroupOrder, isFalse);
    expect(store.partGroups().first.key, first);
  });

  testWidgets('the timeline grip saves the same order', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = sampleCatalogue(now);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.timeline,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    final first = store.partGroups().first.key;
    await t.drag(find.byKey(Key('tl-grip-$first')), const Offset(0, 150));
    await t.pumpAndSettle();
    expect(store.hasGroupOrder, isTrue);
    expect(store.partGroups().first.key, isNot(first));
  });

  group('window edges', () {
    // One open part moved around the edges of each window.
    PartGroup edge(void Function(CatalogueStore s, PartGroup g) move) {
      final s = sampleCatalogue(now);
      final g = s.partGroups().firstWhere(
        (g) => g.kind == GroupKind.part && g.status.isOpen,
      );
      move(s, g);
      return s.partGroups(includeDone: true).firstWhere((x) => x.key == g.key);
    }

    bool inRange(PartGroup g, DueRange r) =>
        ViewFilter(range: r).matches(g, now, const {});

    DateTime dayEnd(int days) =>
        DateTime(now.year, now.month, now.day + days, 23, 59);

    test('day 14 is within two weeks, day 15 later', () {
      final at14 = edge(
        (s, g) => s.setPartDue(g.partId!, g.stageId, dayEnd(14)),
      );
      expect(inRange(at14, DueRange.within14), isTrue);
      expect(inRange(at14, DueRange.later), isFalse);
      final at15 = edge(
        (s, g) => s.setPartDue(g.partId!, g.stageId, dayEnd(15)),
      );
      expect(inRange(at15, DueRange.later), isTrue);
    });

    test('handed-in work leaves every deadline window', () {
      final sent = edge((s, g) {
        s.setPartDue(g.partId!, g.stageId, dayEnd(1));
        s.setStatusMany([for (final t in g.tasks) t.id], TaskStatus.submitted);
      });
      for (final r in DueRange.values.where((r) => r != DueRange.all)) {
        expect(inRange(sent, r), isFalse, reason: r.name);
      }
    });

    test('today holds work whose start has come, not work starting later', () {
      final started = edge(
        (s, g) => s.setPartPlan(
          g.partId!,
          g.stageId,
          start: dayEnd(-1),
          end: dayEnd(2),
        ),
      );
      expect(inRange(started, DueRange.today), isTrue);
      final later = edge(
        (s, g) => s.setPartPlan(
          g.partId!,
          g.stageId,
          start: DateTime(now.year, now.month, now.day + 1),
          end: dayEnd(3),
        ),
      );
      expect(inRange(later, DueRange.today), isFalse);
    });
  });
}
