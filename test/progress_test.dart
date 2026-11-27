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
  });
}
