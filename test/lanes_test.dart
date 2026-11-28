import 'package:anisched/src/models/lanes.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(int day) => DateTime(2026, 12, day);
  Span s(String k, int from, int to) => Span(k, d(from), d(to));
  DateTime u(int day) => DateTime.utc(2026, 12, day);

  test('non-overlapping bars share a lane; a bar may start the day after', () {
    final l = layoutLanes([s('a', 1, 3), s('b', 4, 6), s('c', 7, 7)], 2);
    expect(l.laneOf, {'a': 0, 'b': 0, 'c': 0});
    expect(l.usedLanes, 1);
    expect(l.overflow, isEmpty);
  });

  test('overlaps take the lowest free lane, as few lanes as needed', () {
    final l = layoutLanes([
      s('a', 1, 5),
      s('b', 2, 3),
      s('c', 4, 8),
      s('d', 6, 9),
    ], 3);
    expect(l.laneOf, {'a': 0, 'b': 1, 'c': 1, 'd': 0});
    expect(l.usedLanes, 2);
  });

  test('past the limit: overflow bars and over-limit days', () {
    final l = layoutLanes([
      s('a', 1, 10),
      s('b', 3, 6),
      s('c', 5, 8),
      s('e', 12, 12),
    ], 2);
    expect(l.overflow, {'c'});
    expect(l.overflowRanges, [(start: u(5), end: u(6))]);
    final counts = {for (final b in l.busyDays) b.day.day: b.count};
    expect(counts[1], 1);
    expect(counts[5], 3);
    expect(counts[9], 1);
    expect(counts.containsKey(11), isFalse); // nothing that day
    expect(counts[12], 1);
  });

  test('ties: the longer bar first, then by key', () {
    final l = layoutLanes([s('z', 1, 2), s('y', 1, 9), s('x', 1, 2)], 3);
    expect(l.spans.map((s) => s.key), ['y', 'x', 'z']);
    expect(l.laneOf, {'y': 0, 'x': 1, 'z': 2});
  });

  test('a backwards span is refused', () {
    expect(() => s('a', 5, 4), throwsArgumentError);
    expect(() => layoutLanes([], 0), throwsArgumentError);
  });

  test('the calendar lays out open units on the lanes setting', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    final store = CatalogueStore(db, clock: () => DateTime(2026, 11, 27, 9));
    final w = store.createWork('W');
    final ep = store.addEpisode(w, '#1');
    final lo = store.stages(w).firstWhere((s) => s.name == 'LO').id;
    int part(String label, int dueDay) {
      final p = store.addPart(ep, label);
      store
        ..addCut(ep, 'C$label', partId: p)
        ..addTasksForPart(p, lo)
        ..setPartDue(p, lo, DateTime(2026, 11, dueDay));
      return p;
    }

    // Kickoff defaults to 11/27 for all three.
    part('A', 29);
    final b = part('B', 30);
    part('C', 30);
    store.settings.parallelLanes = 2;
    var cal = store.calendarLayout(basis: CalendarBasis.production);
    expect(cal.layout.lanes, 2);
    expect(cal.layout.overflow, hasLength(1));
    expect(cal.unplaced, isEmpty);

    // On the work basis, B's own plan takes it out of the crowd — but a
    // bar never changes lane by itself: only 「자동 정렬」 re-lays it.
    store.setPartPlan(
      b,
      lo,
      start: DateTime(2026, 12, 1),
      end: DateTime(2026, 12, 2),
    );
    cal = store.calendarLayout();
    expect(cal.layout.overflow, hasLength(1));
    store.clearLanePins();
    expect(store.calendarLayout().layout.overflow, isEmpty);
    // A unit with no deadline cannot be placed.
    final p = store.addPart(ep, 'D');
    store
      ..addCut(ep, 'CD', partId: p)
      ..addTasksForPart(p, lo);
    expect(store.calendarLayout().unplaced, hasLength(1));
    expect(() => store.settings.parallelLanes = 0, throwsRangeError);
  });

  test('lane names follow the lane count; unnamed lanes are null', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    final settings = CatalogueStore(db).settings;
    expect(settings.parallelLanes, 2);
    expect(settings.laneNames, [null, null]);
    settings.laneNames = ['메인', '', '서브', '여분'];
    expect(settings.laneNames, ['메인', null]);
    settings.parallelLanes = 3;
    expect(settings.laneNames, ['메인', null, '서브']);
    settings.parallelLanes = 4;
    expect(settings.laneNames, ['메인', null, '서브', '여분']);
    settings.parallelLanes = 5;
    expect(settings.laneNames.last, isNull);
  });

  test('the mock-up rule: earliest start first, first lane that is free', () {
    // Lane 0 ends 12/5; lane 1 ends 12/3. A bar from 12/4 fits lane 1
    // only; a bar from 12/4 when both are busy overflows.
    final l = layoutLanes([
      s('a', 1, 5),
      s('b', 1, 3),
      s('c', 4, 6),
      s('d', 4, 4),
    ], 2);
    expect(l.laneOf['a'], 0);
    expect(l.laneOf['b'], 1);
    expect(l.laneOf['c'], 1);
    expect(l.overflow, {'d'});
  });

  group('pins', () {
    test('a pinned bar keeps its lane; the rest fill around it', () {
      final l = layoutLanes(
        [s('a', 1, 5), s('b', 2, 3), s('c', 4, 6)],
        2,
        pinned: {'b': 0},
      );
      // b holds lane 0 on 12/2–3; a cannot share it, so a takes lane 1;
      // c (12/4–6) fits lane 0 after b.
      expect(l.laneOf, {'b': 0, 'a': 1, 'c': 0});
      expect(l.pinned, {'b'});
      expect(l.overflow, isEmpty);
    });

    test('a gap left by a pin can be filled', () {
      final l = layoutLanes(
        [s('late', 10, 12), s('early', 1, 3)],
        1,
        pinned: {'late': 0},
      );
      expect(l.laneOf, {'late': 0, 'early': 0});
    });

    test('clashing pins stay and are marked; pins past the count overflow', () {
      final l = layoutLanes(
        [s('a', 1, 5), s('b', 3, 4), s('c', 1, 1), s('d', 9, 9)],
        2,
        pinned: {'a': 0, 'b': 0, 'c': 7, 'd': 0},
      );
      expect((l.laneOf['a'], l.laneOf['b'], l.laneOf['d']), (0, 0, 0));
      expect(l.overlapping, {'a', 'b'});
      expect(l.overflow, {'c'});
    });

    test('the store saves pins by group key and can clear them', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = CatalogueStore(db, clock: () => DateTime(2026, 11, 27, 9));
      final w = store.createWork('W');
      final ep = store.addEpisode(w, '#1');
      final lo = store.stages(w).firstWhere((s) => s.name == 'LO').id;
      for (final label in ['A', 'B']) {
        final p = store.addPart(ep, label);
        store
          ..addCut(ep, 'C$label', partId: p)
          ..addTasksForPart(p, lo)
          ..setPartDue(p, lo, DateTime(2026, 11, 30));
      }
      final keys = [for (final g in store.partGroups()) g.key];
      expect(store.calendarLayout().layout.laneOf[keys[0]], 0);
      store.pinLane(keys[0], 1);
      var lanes = store.calendarLayout().layout.laneOf;
      expect((lanes[keys[0]], lanes[keys[1]]), (1, 0));
      store.unpinLane(keys[0]);
      expect(store.calendarLayout().layout.laneOf[keys[0]], 0);
      store
        ..pinLane(keys[0], 1)
        ..pinLane(keys[1], 1);
      final both = store.calendarLayout().layout;
      expect(both.overflow, isEmpty);
      expect(both.overlapping, keys.toSet());
      store.clearLanePins();
      lanes = store.calendarLayout().layout.laneOf;
      expect(lanes.values.toSet(), {0, 1});
    });
  });

  test('changing dates keeps every bar in its lane; new bars find room', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    final store = CatalogueStore(db, clock: () => DateTime(2026, 11, 27, 9));
    final w = store.createWork('W');
    final ep = store.addEpisode(w, '#1');
    final lo = store.stages(w).firstWhere((s) => s.name == 'LO').id;
    int part(String label, int start, int end) {
      final p = store.addPart(ep, label);
      store
        ..addCut(ep, 'C$label', partId: p)
        ..addTasksForPart(p, lo)
        ..setPartSchedule(
          p,
          lo,
          kickoffAt: DateTime(2026, 12, start),
          dueAt: DateTime(2026, 12, end),
        );
      return p;
    }

    final a = part('A', 1, 5);
    part('B', 3, 8);
    Map<String?, int> lanes() {
      final l = store.calendarLayout(basis: CalendarBasis.production).layout;
      return {
        for (final g in store.partGroups()) g.partLabel: l.laneOf[g.key]!,
      };
    }

    expect(lanes(), {'A': 0, 'B': 1});
    // A moves after B: fresh placement would swap them; it stays.
    store.setPartSchedule(
      a,
      lo,
      kickoffAt: DateTime(2026, 12, 6),
      dueAt: DateTime(2026, 12, 7),
    );
    expect(lanes(), {'A': 0, 'B': 1});
    // A new bar takes the first lane with room (A left 12/1–2 free).
    part('C', 1, 2);
    expect(lanes()['C'], 0);
    // 「자동 정렬」 lays everything out afresh.
    store.clearLanePins();
    expect(lanes(), {'C': 0, 'B': 0, 'A': 1});
    // The cheap check that lets date writes skip the work agrees with it:
    // held after holding (its keys are the groups' keys), not after a new
    // unit or a cleared pin.
    expect(store.placesHeld, isFalse);
    store.holdPlaces();
    expect(store.placesHeld, isTrue);
    final ep2 = store.addEpisode(w, '#2');
    final d = store.addPart(ep2, 'D');
    store
      ..addCut(ep2, 'CD', partId: d)
      ..addTasksForPart(d, lo);
    expect(store.placesHeld, isFalse);
    store.holdPlaces();
    expect(store.placesHeld, isTrue);
    store.unpinLane(store.partGroups().first.key);
    expect(store.placesHeld, isFalse);
  });

  test('lines: add, rename, remove; pins follow the removal', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    final store = CatalogueStore(db);
    expect(store.lanes(), [null, null]);
    expect(store.addLane(name: 'TV'), 2);
    store.renameLane(0, 'movie');
    expect(store.lanes(), ['movie', null, 'TV']);
    store
      ..pinLane('a', 0)
      ..pinLane('b', 1)
      ..pinLane('c', 2)
      ..removeLane(1);
    expect(store.lanes(), ['movie', 'TV']);
    expect(store.settings.parallelLanes, 2);
    final pins = {
      for (final r in db.select('SELECT group_key, lane FROM lane_pins'))
        r['group_key'] as String: r['lane'] as int,
    };
    expect(pins, {'a': 0, 'c': 1}); // b let go, c moved down
    store.removeLane(0);
    expect(() => store.removeLane(0), throwsStateError);
    expect(() => store.renameLane(3, 'x'), throwsRangeError);
  });
}
