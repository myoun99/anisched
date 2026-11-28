import 'package:anisched/src/controllers/lanes.dart';
import 'package:anisched/src/models/lanes.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

LaneLayout layoutOf(CatalogueStore s) =>
    s.calendarLayout(basis: CalendarBasis.work).layout;

void main() {
  group('lanes', () {
    test('added at the bottom, unnamed, up to the limit', () {
      final s = sampleCatalogue(now);
      final before = s.settings.parallelLanes;
      expect(addLane(s), isTrue);
      expect(s.settings.parallelLanes, before + 1);
      expect(s.settings.laneNames.last, isNull);
      s.settings.parallelLanes = maxLanes;
      expect(addLane(s), isFalse);
    });

    test('a blank name gives the number back', () {
      final s = sampleCatalogue(now);
      renameLane(s, 0, ' 原画 ');
      expect(s.settings.laneNames.first, '原画');
      renameLane(s, 0, '  ');
      expect(s.settings.laneNames.first, isNull);
    });

    test('removing one moves the lanes below up, names and pins too', () {
      final s = sampleCatalogue(now);
      s.settings.parallelLanes = 3;
      s.settings.laneNames = ['A', 'B', 'C'];
      final keys = s.partGroups().map((g) => g.key).take(2).toList();
      s.pinLane(keys[0], 1);
      s.pinLane(keys[1], 2);
      expect(removeLane(s, layoutOf(s), 1), isTrue);
      expect(s.settings.parallelLanes, 2);
      expect(s.settings.laneNames, ['A', 'C']);
      final after = layoutOf(s);
      expect(after.pinned, {
        keys[1],
      }, reason: 'work on the removed lane is free');
      expect(after.laneOf[keys[1]], 1, reason: 'moved up with its lane');
    });

    test('the last lane stays', () {
      final s = sampleCatalogue(now);
      s.settings.parallelLanes = 1;
      expect(removeLane(s, layoutOf(s), 0), isFalse);
      expect(s.settings.parallelLanes, 1);
    });
  });

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
