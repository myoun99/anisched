// Edges that hand-made mutants survived (docs/testing.md): each test
// fails when the boundary it names moves by one.
import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/cut_numbers.dart';
import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/models/lanes.dart';
import 'package:anisched/src/models/progress.dart';
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
        row(1, status: TaskStatus.done, due: DateTime(2026, 11, 2)),
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
}
