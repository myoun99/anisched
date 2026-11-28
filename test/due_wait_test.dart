import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late CatalogueStore store;
  var now = DateTime(2026, 11, 2, 10);

  setUp(() {
    now = DateTime(2026, 11, 2, 10);
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now.toUtc());
  });
  tearDown(() => db.close());

  int stage(int w, String name) =>
      store.stages(w).firstWhere((s) => s.name == name).id;

  ({int w, int part, int stage, List<int> tasks}) part4() {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C001~C004', partLabel: 'A');
    final s = stage(w, '원화');
    store.addTasksForPart(r.partId!, s);
    final tasks = [
      for (final t in store.taskRows())
        if (t.stageId == s) t.id,
    ];
    return (w: w, part: r.partId!, stage: s, tasks: tasks);
  }

  group('deadline revisions', () {
    test('extend adds a revision in force; the first can be corrected', () {
      final p = part4();
      final target = DueTarget.part(p.part, p.stage);
      store.setPartDue(p.part, p.stage, DateTime(2026, 11, 10));
      expect(store.dueRevisions(target).single.revision, 1);

      now = DateTime(2026, 11, 8);
      expect(store.extendDue(target, DateTime(2026, 11, 17)), 2);
      var g = store.partGroups().single;
      expect(g.dueAt, DateTime(2026, 11, 17).toUtc());
      expect(g.dueRevision, 2);
      expect(g.firstDueAt, DateTime(2026, 11, 10).toUtc());
      expect(g.tasks.first.dueExtensions, 1);

      // Correcting the 1st does not touch the deadline in force.
      store.editDueRevision(target, 1, DateTime(2026, 11, 11));
      g = store.partGroups().single;
      expect(g.dueAt, DateTime(2026, 11, 17).toUtc());
      expect(g.firstDueAt, DateTime(2026, 11, 11).toUtc());

      // Plain setPartDue corrects the revision in force.
      store.setPartDue(p.part, p.stage, DateTime(2026, 11, 18));
      expect(store.dueRevisions(target).map((r) => r.revision), [1, 2]);
      expect(store.partGroups().single.dueAt, DateTime(2026, 11, 18).toUtc());

      // Removing the last falls back to the one before.
      store.removeDueRevision(target, 2);
      g = store.partGroups().single;
      expect(g.dueAt, DateTime(2026, 11, 11).toUtc());
      expect(g.dueRevision, 1);
      store.removeDueRevision(target, 1);
      expect(store.partGroups().single.dueAt, isNull);
      expect(() => store.removeDueRevision(target, 1), throwsStateError);
    });

    test('removing a middle revision renumbers the later ones', () {
      final p = part4();
      final target = DueTarget.part(p.part, p.stage);
      store
        ..extendDue(target, DateTime(2026, 11, 10))
        ..extendDue(target, DateTime(2026, 11, 12))
        ..extendDue(target, DateTime(2026, 11, 14))
        ..removeDueRevision(target, 2);
      expect(store.dueRevisions(target).map((r) => (r.revision, r.dueAt)), [
        (1, DateTime(2026, 11, 10).toUtc()),
        (2, DateTime(2026, 11, 14).toUtc()),
      ]);
      // Removing the first moves every later one down.
      store
        ..extendDue(target, DateTime(2026, 11, 16))
        ..removeDueRevision(target, 1);
      expect(store.dueRevisions(target).map((r) => r.revision), [1, 2]);
      expect(
        store.dueRevisions(target).first.dueAt,
        DateTime(2026, 11, 14).toUtc(),
      );
    });

    test("a cut's own deadline continues its part's revisions", () {
      final p = part4();
      store.setPartDue(p.part, p.stage, DateTime(2026, 11, 10));
      store.extendDue(DueTarget.task(p.tasks[2]), DateTime(2026, 11, 20));
      final row = store.taskRows().firstWhere((t) => t.id == p.tasks[2]);
      expect(row.dueAt, DateTime(2026, 11, 20).toUtc());
      expect(row.dueRevision, 2);
      expect(row.firstDueAt, DateTime(2026, 11, 10).toUtc());
      store.setTaskDue(p.tasks[2], null);
      final back = store.taskRows().firstWhere((t) => t.id == p.tasks[2]);
      expect(back.dueAt, DateTime(2026, 11, 10).toUtc());
      expect(back.dueRevision, 1);
      expect(store.dueRevisions(DueTarget.task(p.tasks[2])), isEmpty);
    });

    test('a task made with a deadline has its first revision', () {
      final w = store.createWork('W');
      final r = store.addEpisodeWithCuts(w, '#1', 'C001');
      final t = store.addTask(
        stage(w, '원화'),
        cutId: r.cutIds.single,
        dueAt: DateTime(2026, 11, 9),
      );
      expect(store.dueRevisions(DueTarget.task(t)).single.revision, 1);
    });

    test('statistics: against the first deadline, extensions', () {
      final p = part4();
      final target = DueTarget.part(p.part, p.stage);
      store.setPartDue(p.part, p.stage, DateTime(2026, 11, 4, 18));
      store.extendDue(target, DateTime(2026, 11, 6, 18));
      now = DateTime(2026, 11, 5, 12); // late on the 1st, on time on the 2nd
      store.setStatus(p.tasks[0], TaskStatus.submitted);
      now = DateTime(2026, 11, 9);
      final s = store.stats(
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 9),
      );
      expect(s.lateness, {-1: 1});
      expect(s.latenessFirst, {1: 1});
      expect(s.onTime, 1);
      expect(s.lateFirst, 1);
      expect(s.extensions, {1: 1});
      expect(s.extendedDays, {2: 1});
    });
  });

  group('waiting', () {
    test('a part on hold: in hand drops, pace still counts every cut', () {
      final p = part4();
      store.setPartDue(p.part, p.stage, DateTime(2026, 11, 13));
      final paceBefore = store.paceOf(store.partGroups().single)!.remaining;

      store.setPartWaiting(
        p.part,
        p.stage,
        waiting: true,
        reason: '3D LO',
        until: DateTime(2026, 11, 5),
      );
      var g = store.partGroups().single;
      expect(g.partWaiting, isTrue);
      expect(g.partWaitReason, '3D LO');
      expect(g.waiting, 4);
      expect(g.inHand, 0);
      expect(store.paceOf(g)!.remaining, paceBefore);
      expect(store.holding(), (inHand: 0, waiting: 4));

      // One cut arrives early: its own setting overrides the part.
      store.setTaskWaiting(p.tasks[0], waiting: false);
      g = store.partGroups().single;
      expect(g.inHand, 1);
      expect(g.waiting, 3);
      expect(g.tasks.first.waitingFromPart, isFalse);

      // The part comes off hold; the overrides still decide for themselves.
      store.setPartWaiting(p.part, p.stage, waiting: false);
      store.setWaitingMany([p.tasks[3]], waiting: true, reason: 'ref');
      g = store.partGroups().single;
      expect(g.inHand, 3);
      expect(g.tasks.last.waitReason, 'ref');
      store.followPartWaiting(p.tasks);
      expect(store.holding(), (inHand: 4, waiting: 0));
    });

    test('handed cuts are neither in hand nor waiting', () {
      final p = part4();
      store.setPartWaiting(p.part, p.stage, waiting: true);
      store.setStatus(p.tasks[0], TaskStatus.submitted);
      expect(store.holding(), (inHand: 0, waiting: 3));
    });
  });

  test('v12 makes existing deadlines revision 1', () {
    final raw = sqlite3.openInMemory()..execute('PRAGMA foreign_keys = ON;');
    migrate(raw, steps: migrations.where((m) => m.version <= 11).toList());
    final s = CatalogueStore(raw);
    final w = s.createWork('W');
    final r = s.addEpisodeWithCuts(w, '#1', 'C001~C002', partLabel: 'A');
    final st = s.stages(w).first.id;
    raw.execute(
      'INSERT INTO part_stage_dues (part_id, stage_id, due_at) VALUES (?, ?, 1);',
      [r.partId, st],
    );
    raw.execute(
      'INSERT INTO tasks (stage_id, cut_id, due_at) VALUES (?, ?, 2);',
      [st, r.cutIds.first],
    );
    migrate(raw);
    expect(
      raw
          .select('SELECT COUNT(*) FROM due_revisions WHERE revision = 1')
          .first
          .columnAt(0),
      2,
    );
    raw.close();
  });
}
