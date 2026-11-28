// Edges that hand-made mutants survived (docs/testing.md): each test
// fails when the boundary it names moves by one.
import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/cut_numbers.dart';
import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/models/lanes.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/models/stats.dart';
import 'package:flutter_test/flutter_test.dart';

TaskRow row(
  int id, {
  TaskStatus status = TaskStatus.received,
  DateTime? due,
  DateTime? planStart,
  DateTime? planEnd,
  bool partWaiting = false,
}) => TaskRow(
  id: id,
  status: status,
  take: 1,
  workId: 1,
  workTitle: 'W',
  currency: 'JPY',
  episodeId: 1,
  episodeNumber: '#1',
  stageId: 1,
  stageName: '원화',
  cutId: id,
  cutNumber: 'C$id',
  partId: 1,
  partLabel: 'A',
  partDueAt: due,
  partPlanStartAt: planStart,
  partPlanEndAt: planEnd,
  partWaiting: partWaiting,
);

void main() {
  final now = DateTime(2026, 11, 4, 12); // Wednesday

  group('pace and signals', () {
    test('nothing left past the end is not behind', () {
      final g = PartGroup([
        row(1, status: TaskStatus.submitted, due: DateTime(2026, 11, 2)),
      ]);
      final pace = paceFor(g, now)!;
      expect(pace.workDays, 0);
      expect(pace.behind, isFalse);
    });

    test('due today is zero days left, not late', () {
      final g = PartGroup([row(1, due: DateTime(2026, 11, 4, 18))]);
      expect(dueSignal(g, now: now), isA<DueDaysLeft>());
      expect((dueSignal(g, now: now) as DueDaysLeft).days, 0);
    });

    test('a plan ending on the deadline day is not over it', () {
      final g = PartGroup([
        row(
          1,
          due: DateTime(2026, 11, 6, 18),
          planStart: DateTime(2026, 11, 5),
          planEnd: DateTime(2026, 11, 6),
        ),
      ]);
      expect(g.slackDays, 0);
      expect(planSignal(g, now: now), isNot(isA<PlanOver>()));
    });

    test('a planned start of today, not begun, is a late start', () {
      final g = PartGroup([
        row(1, due: DateTime(2026, 11, 9), planStart: DateTime(2026, 11, 4)),
      ]);
      expect(planSignal(g, now: now), isA<PlanLateStart>());
    });

    test('a handed cut in a part on hold is not counted as waiting', () {
      final g = PartGroup([
        row(1, partWaiting: true),
        row(2, status: TaskStatus.submitted, partWaiting: true),
      ]);
      expect(g.waiting, 1);
      expect(g.inHand, 0);
    });
  });

  test('a bar starting on the day another ends needs another lane', () {
    final l = layoutLanes([
      Span('a', DateTime(2026, 11, 2), DateTime(2026, 11, 4)),
      Span('b', DateTime(2026, 11, 4), DateTime(2026, 11, 5)),
    ], 2);
    expect(l.laneOf, {'a': 0, 'b': 1});
  });

  test('exact per-second pay rounds the amount half up', () {
    const rate = Rate(RateUnit.perSecond, 3);
    expect(rate.payFor(lengthMs: 1500, rounding: SecondsRounding.exact), 5);
  });

  test('ranges and runs stop exactly at the limit', () {
    final atLimit = parseCutNumbers('C1~C$maxCutRange');
    expect(atLimit.numbers, hasLength(maxCutRange));
    expect(atLimit.errors, isEmpty);
    final past = parseCutNumbers('C1~C${maxCutRange + 1}');
    expect(past.numbers, isEmpty);
    expect(past.errors, hasLength(1));
    expect(cutNumberRun(start: 1, count: maxCutRange), hasLength(maxCutRange));
    expect(
      () => cutNumberRun(start: 1, count: maxCutRange + 1),
      throwsA(anything),
    );
  });

  test('no modification time never proves a file unchanged', () {
    const known = DocumentFingerprint(size: 10, hash: 1);
    expect(known.sameStat((size: 10, modifiedMs: null)), isFalse);
  });

  group('statistics days', () {
    StatsFact plan(String key, DateTime start, DateTime end) => StatsFact(
      taskId: key.hashCode,
      stageName: 'LO',
      workId: 1,
      workTitle: 'W',
      currency: 'JPY',
      groupKey: key,
      planStartAt: start,
      planEndAt: end,
    );

    test('planned groups per day: clipped to the range, ends included', () {
      final s = computeStats(
        facts: [
          plan('inside', DateTime(2026, 11, 3), DateTime(2026, 11, 4)),
          plan('before', DateTime(2026, 10, 20), DateTime(2026, 11, 2)),
          plan('after', DateTime(2026, 11, 6), DateTime(2026, 12, 20)),
          plan('gone', DateTime(2026, 10, 1), DateTime(2026, 10, 5)),
          plan('later', DateTime(2026, 11, 9), DateTime(2026, 11, 12)),
        ],
        intervals: const [],
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 9),
        now: DateTime(2026, 11, 9),
      );
      expect(s.days.map((d) => d.planned), [1, 1, 1, 0, 1, 1, 1]);
    });

    test('before the day start, an instant belongs to the day before', () {
      expect(
        workDayOf(DateTime(2026, 11, 4, 4, 59), 300),
        DateTime(2026, 11, 3),
      );
      expect(workDayOf(DateTime(2026, 11, 4, 5), 300), DateTime(2026, 11, 4));
    });
  });
}
