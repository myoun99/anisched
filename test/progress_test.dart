import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('deriveStatus', () {
    Map<TaskStatus, int> c(List<TaskStatus> l) {
      final m = <TaskStatus, int>{};
      for (final s in l) {
        m[s] = (m[s] ?? 0) + 1;
      }
      return m;
    }

    const r = TaskStatus.received;
    const w = TaskStatus.inProgress;
    const s = TaskStatus.submitted;
    const t = TaskStatus.retake;
    const d = TaskStatus.done;

    test('follows the design rules', () {
      expect(deriveStatus(c([d, d])), d);
      expect(deriveStatus(c([d, t, w])), t);
      expect(deriveStatus(c([s, d])), s);
      expect(deriveStatus(c([r, r])), r);
      expect(deriveStatus(c([r, w])), w);
      expect(deriveStatus(c([r, d])), w);
      expect(deriveStatus(c([])), r);
    });
  });

  test('dueInDays counts working days and honours the day start', () {
    final now = DateTime(2026, 11, 27, 14);
    expect(dueInDays(DateTime(2026, 11, 27, 23), now, 0), 0);
    expect(dueInDays(DateTime(2026, 11, 30, 1), now, 0), 3);
    expect(dueInDays(DateTime(2026, 11, 25), now, 0), -2);
    // With days starting at 05:00, 01:00 on the 28th is still the 27th.
    expect(dueInDays(DateTime(2026, 11, 28, 1), now, 300), 0);
  });

  group('CatalogueStore views', () {
    late Database db;
    late DateTime now;
    late CatalogueStore store;
    late int work;
    late int ep;
    late int lo;
    late int genga;

    setUp(() {
      db = openAppDatabase(':memory:');
      now = DateTime(2026, 11, 27, 14);
      store = CatalogueStore(db, clock: () => now);
      work = store.createWork('별빛 정류장');
      ep = store.addEpisode(work, '#07');
      final stages = store.stages(work);
      lo = stages.firstWhere((s) => s.name == 'LO').id;
      genga = stages.firstWhere((s) => s.name == '원화').id;
    });
    tearDown(() => db.close());

    int partWithCuts(String label, List<String> cuts, int stage, int dueDays) {
      final part = store.addPart(ep, label);
      for (final c in cuts) {
        store.addCut(ep, c, partId: part, lengthMs: 3000);
      }
      store
        ..setPartDue(part, stage, now.add(Duration(days: dueDays)))
        ..addTasksForPart(part, stage);
      return part;
    }

    List<int> tasksOf(int part, int stage) => [
      for (final r in db.select(
        'SELECT t.id FROM tasks t JOIN cuts c ON c.id = t.cut_id '
        'WHERE c.part_id = ? AND t.stage_id = ? ORDER BY c.sort_key',
        [part, stage],
      ))
        r['id'] as int,
    ];

    test('a part × stage rolls up counts, handed, status, pay and time', () {
      store.setEpisodeRate(ep, genga, const Rate(RateUnit.fixed, 4500));
      final part = partWithCuts(
        'B파트',
        ['C033', 'C030', 'C031', 'C032'],
        genga,
        2,
      );
      final ids = tasksOf(part, genga); // C030, C031, C032, C033
      store
        ..setStatus(ids[0], TaskStatus.submitted)
        ..setStatus(ids[1], TaskStatus.done)
        ..setStatus(ids[2], TaskStatus.done)
        ..setStatus(ids[3], TaskStatus.inProgress)
        ..requestRetake(ids[0], paidAmount: 500);
      store.setStatus(ids[0], TaskStatus.submitted);

      final timer = WorkTimerStore(db, clock: () => now.toUtc());
      timer.start(taskId: ids[3]);
      now = now.add(const Duration(minutes: 90));

      final g = store.partGroups().single;
      expect(g.partLabel, 'B파트');
      expect(g.stageName, '원화');
      expect(g.kind, GroupKind.part);
      expect(g.total, 4);
      expect(g.handed, 3);
      expect(g.status, TaskStatus.inProgress);
      expect(g.counts, {
        TaskStatus.submitted: 1,
        TaskStatus.done: 2,
        TaskStatus.inProgress: 1,
      });
      expect(g.pay, 4 * 4500 + 500);
      expect(g.unpriced, 0);
      expect(g.currency, 'JPY');
      expect(g.worked, const Duration(minutes: 90));
      expect(g.tasks.map((t) => t.cutNumber), ['C030', 'C031', 'C032', 'C033']);
      expect(g.tasks.first.take, 2);
    });

    test('pay uses the rounding setting and counts the unpriced', () {
      store.setEpisodeRate(ep, lo, const Rate(RateUnit.perSecond, 1000));
      final part = store.addPart(ep, 'A파트');
      store
        ..addCut(ep, 'C1', partId: part, lengthMs: 2500)
        ..addCut(ep, 'C2', partId: part)
        ..addTasksForPart(part, lo);
      final g = store.partGroups().single;
      expect(g.pay, 3000);
      expect(g.unpriced, 1);
    });

    test(
      'a storyboard is a unit alone; part-less cuts share a no-part unit',
      () {
        final conte = store.stages(work).first.id;
        final sb = store.addStoryboard(ep, '콘티');
        final due1 = now.add(const Duration(days: 3)).toUtc();
        final due2 = now.add(const Duration(days: 1)).toUtc();
        store
          ..addTask(conte, storyboardId: sb)
          ..addTask(lo, cutId: store.addCut(ep, 'C901'), dueAt: due1)
          ..addTask(lo, cutId: store.addCut(ep, 'C900'), dueAt: due2)
          ..addTask(genga, cutId: store.addCut(ep, 'C902'));
        final groups = store.partGroups();
        expect(groups.map((g) => g.kind), [
          GroupKind.noPart, // LO, earliest cut due in 1 day
          GroupKind.storyboard, // no deadline, earlier in display order
          GroupKind.noPart, // 원화, no deadline
        ]);
        final loNoPart = groups.first;
        expect(loNoPart.partLabel, isNull);
        expect(loNoPart.stageName, 'LO');
        expect(loNoPart.dueAt, due2);
        expect(loNoPart.tasks.map((t) => t.unitLabel), ['C900', 'C901']);
        expect(loNoPart.tasks.first.dueFromPart, isFalse);
        expect(groups[1].storyboardLabel, '콘티');
        expect(groups[1].tasks.single.unitLabel, '콘티');
      },
    );

    test('groups come in deadline order, no deadline last', () {
      partWithCuts('late', ['C1'], lo, 5);
      store.addPart(ep, 'empty-no-tasks');
      final noDue = store.addPart(ep, 'nodue');
      store
        ..addCut(ep, 'C2', partId: noDue)
        ..addTasksForPart(noDue, lo);
      partWithCuts('early', ['C3'], genga, 1);
      final groups = store.partGroups();
      expect(groups.map((g) => g.partLabel), ['early', 'late', 'nodue']);
      expect(groups.first.tasks.single.dueFromPart, isTrue);
    });

    test('a cut deadline override shows on the row, not the group', () {
      final part = partWithCuts('C파트', ['C044', 'C045'], lo, 4);
      final ids = tasksOf(part, lo);
      final own = now.add(const Duration(days: 1)).toUtc();
      db.execute('UPDATE tasks SET due_at = ? WHERE id = ?', [
        own.millisecondsSinceEpoch,
        ids[0],
      ]);
      final g = store.partGroups().single;
      expect(g.dueAt, now.add(const Duration(days: 4)).toUtc());
      expect(g.tasks[0].dueOverridden, isTrue);
      expect(g.tasks[0].dueAt, own);
      expect(g.tasks[1].dueOverridden, isFalse);
    });

    test('today: due soon or active, sorted by days left then urgency', () {
      // Due in 2 days, received → in (due soon).
      final soon = partWithCuts('soon', ['C1'], lo, 2);
      // Due in 10 days but in progress → in (active).
      final active = partWithCuts('active', ['C2'], lo, 10);
      store.setStatus(tasksOf(active, lo).single, TaskStatus.inProgress);
      // Due in 10 days, untouched → out.
      partWithCuts('later', ['C3'], lo, 10);
      // Due in 2 days but all submitted → out.
      final handed = partWithCuts('handed', ['C4'], lo, 2);
      store.setStatus(tasksOf(handed, lo).single, TaskStatus.submitted);
      // Late, received → in, first.
      partWithCuts('late', ['C5'], lo, -1);
      // Due in 2 days with a retake → before 'soon' (more urgent).
      final retake = partWithCuts('retake', ['C6'], lo, 2);
      store.requestRetake(tasksOf(retake, lo).single);

      final t = store.today();
      expect(t.entries.map((e) => e.group.partLabel), [
        'late',
        'retake',
        'soon',
        'active',
      ]);
      expect(t.entries.map((e) => e.dueInDays), [-1, 2, 2, 10]);
      expect(t.late, 1);
      expect(soon, isPositive);
    });

    test('today counts late overridden cuts and respects the horizon', () {
      final part = partWithCuts('B', ['C1', 'C2'], lo, 6);
      final ids = tasksOf(part, lo);
      db.execute('UPDATE tasks SET due_at = ? WHERE id = ?', [
        now.subtract(const Duration(days: 1)).toUtc().millisecondsSinceEpoch,
        ids[0],
      ]);
      expect(store.today().entries, isEmpty);
      expect(store.today().late, 1);
      expect(store.today(horizonDays: 6).entries, hasLength(1));
    });

    test('archived works and tasks are left out', () {
      final part = partWithCuts('B', ['C1', 'C2'], lo, 1);
      db.execute('UPDATE tasks SET archived_at = 1 WHERE id = ?', [
        tasksOf(part, lo).first,
      ]);
      expect(store.partGroups().single.total, 1);
      db.execute('UPDATE works SET archived_at = 1');
      expect(store.partGroups(), isEmpty);
    });

    test('my plan sits beside the deadline, part default + cut override', () {
      final part = partWithCuts('B', ['C1', 'C2'], lo, 20); // due in 20 days
      final ids = tasksOf(part, lo);
      final start = DateTime(2026, 12, 7);
      final end = DateTime(2026, 12, 12);
      store.setPartPlan(part, lo, start: start, end: end);

      var g = store.partGroups().single;
      expect(g.planStartAt, start.toUtc());
      expect(g.planEndAt, end.toUtc());
      expect(g.dueAt, now.add(const Duration(days: 20)).toUtc());
      expect(g.slackDays, daysBetween(end, now.add(const Duration(days: 20))));
      expect(g.tasks.every((t) => !t.planOverridden), isTrue);

      // One cut planned to finish later than the part: only its end moves.
      final lateEnd = DateTime(2026, 12, 20);
      store.setTaskPlan(ids[1], end: lateEnd);
      g = store.partGroups().single;
      expect(g.tasks[1].planStartAt, start.toUtc());
      expect(g.tasks[1].planEndAt, lateEnd.toUtc());
      expect(g.tasks[1].planOverridden, isTrue);
      expect(g.tasks[1].slackDays, -3); // due 12/17, planned 12/20
      expect(g.tasks[0].planEndAt, end.toUtc());

      store.setPartPlan(part, lo);
      g = store.partGroups().single;
      expect(g.planStartAt, isNull);
      expect(g.slackDays, isNull);
      expect(g.tasks[1].planEndAt, lateEnd.toUtc());
    });

    test('a plan cannot end before it starts', () {
      final part = partWithCuts('B', ['C1'], lo, 5);
      expect(
        () => store.setPartPlan(
          part,
          lo,
          start: DateTime(2026, 12, 10),
          end: DateTime(2026, 12, 9),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => store.setTaskPlan(
          tasksOf(part, lo).single,
          start: DateTime(2026, 12, 10),
          end: DateTime(2026, 12, 9),
        ),
        throwsArgumentError,
      );
    });

    test('part-less cuts plan from the earliest start to the latest end', () {
      final a = store.addTask(lo, cutId: store.addCut(ep, 'C1'));
      final b = store.addTask(lo, cutId: store.addCut(ep, 'C2'));
      store
        ..setTaskPlan(
          a,
          start: DateTime(2026, 12, 3),
          end: DateTime(2026, 12, 4),
        )
        ..setTaskPlan(
          b,
          start: DateTime(2026, 12, 1),
          end: DateTime(2026, 12, 2),
        )
        ..setTaskDue(a, DateTime(2026, 12, 9));
      final g = store.partGroups().single;
      expect(g.kind, GroupKind.noPart);
      expect(g.planStartAt, DateTime(2026, 12).toUtc());
      expect(g.planEndAt, DateTime(2026, 12, 4).toUtc());
      expect(g.slackDays, 5);
      store.setTaskDue(a, null);
      expect(store.partGroups().single.dueAt, isNull);
    });

    group('pace', () {
      // now = Fri 2026-11-27 14:00.
      test('open cuts over working days, today and the end day included', () {
        final part = partWithCuts(
          'B',
          ['C1', 'C2', 'C3', 'C4', 'C5', 'C6'],
          lo,
          2,
        );
        final ids = tasksOf(part, lo);
        store
          ..setStatus(ids[0], TaskStatus.submitted)
          ..setStatus(ids[1], TaskStatus.done)
          ..requestRetake(ids[0]); // back in hand
        final p = store.paceOf(store.partGroups().single)!;
        expect(p.remaining, 5); // all but the done one
        expect(p.workDays, 3); // Fri, Sat, Sun
        expect(p.perDay, closeTo(5 / 3, 1e-9));
        expect(p.today, closeTo(5 / 3, 1e-9));
      });

      test('rest weekdays are skipped and ask nothing that day', () {
        final part = partWithCuts('B', ['C1', 'C2', 'C3', 'C4'], lo, 4); // Tue
        store.settings.restWeekdays = {6, 7};
        var p = store.paceOf(store.partGroups().single)!;
        expect(p.workDays, 3); // Fri, Mon, Tue
        now = DateTime(2026, 11, 28, 10); // Saturday
        p = store.paceOf(store.partGroups().single)!;
        expect(p.workDays, 2);
        expect(p.today, 0);
        expect(part, isPositive);
      });

      test('a later planned start delays the pace; plan end is the target', () {
        final part = partWithCuts('B', ['C1', 'C2', 'C3', 'C4'], lo, 20);
        store.setPartPlan(
          part,
          lo,
          start: DateTime(2026, 12, 7),
          end: DateTime(2026, 12, 8),
        );
        var p = store.paceOf(store.partGroups().single)!;
        expect(p.startsLater, isTrue);
        expect(p.workDays, 2);
        expect(p.perDay, 2);
        expect(p.today, 0);
        store.settings.paceEnd = PaceEnd.due; // to the deadline instead
        p = store.paceOf(store.partGroups().single)!;
        expect(p.workDays, 11); // 12/7 .. 12/17
      });

      test('past the end: no working day, behind, everything today', () {
        partWithCuts('B', ['C1', 'C2'], lo, -1);
        final p = store.paceOf(store.partGroups().single)!;
        expect(p.workDays, 0);
        expect(p.perDay, isNull);
        expect(p.behind, isTrue);
        expect(p.today, 2);
      });

      test('no end date, no pace', () {
        store.addTask(lo, cutId: store.addCut(ep, 'C1'));
        expect(store.paceOf(store.partGroups().single), isNull);
      });

      test('today sums every open group, even ones not listed', () {
        partWithCuts('A', ['C1', 'C2', 'C3', 'C4'], lo, 1); // 4 over 2 days
        partWithCuts('B', ['C5', 'C6', 'C7'], genga, 2); // 3 over 3 days
        partWithCuts('C', ['C8', 'C9', 'C10', 'C11', 'C12'], lo, 9); // 5/10
        final t = store.today();
        expect(t.entries, hasLength(2)); // C is not due soon nor active
        expect(t.entries.first.pace!.perDay, 2);
        expect(t.cutsToday, closeTo(2 + 1 + 0.5, 1e-9));
      });
    });

    test('today: planned work shows; a later plan dims, never hides', () {
      // Planned to start today, deadline far away, untouched → listed.
      final planned = partWithCuts('planned', ['C1'], lo, 20);
      store.setPartPlan(planned, lo, start: now, end: DateTime(2026, 12, 3));
      // Plan started yesterday and its end has passed → still listed.
      final behind = partWithCuts('behind', ['C2'], lo, 20);
      store.setPartPlan(
        behind,
        lo,
        start: DateTime(2026, 11, 20),
        end: DateTime(2026, 11, 25),
      );
      // Due in 2 days but planned to start 12/7 → listed, dimmed.
      final later = partWithCuts('later', ['C3'], lo, 2);
      store.setPartPlan(later, lo, start: DateTime(2026, 12, 7));
      // Planned 12/7, deadline far, untouched → not listed.
      final future = partWithCuts('future', ['C4'], lo, 20);
      store.setPartPlan(future, lo, start: DateTime(2026, 12, 7));

      final t = store.today();
      final byLabel = {for (final e in t.entries) e.group.partLabel: e};
      expect(byLabel.keys.toSet(), {'planned', 'behind', 'later'});
      expect(byLabel['later']!.beforePlan, isTrue);
      expect(byLabel['later']!.planStarted, isFalse);
      expect(byLabel['planned']!.planStarted, isTrue);
      expect(byLabel['behind']!.planStarted, isTrue);
      expect(byLabel['planned']!.beforePlan, isFalse);
    });
  });
}
