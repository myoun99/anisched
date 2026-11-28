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

    test('follows the design rules', () {
      expect(deriveStatus(c([s, s])), s); // all handed in
      expect(deriveStatus(c([s, t, w])), t); // a retake came back
      expect(deriveStatus(c([r, r])), r);
      expect(deriveStatus(c([r, w])), w);
      expect(deriveStatus(c([r, s])), w);
      expect(deriveStatus(c([])), r);
    });

    test('four statuses; submitted is out of hand, the rest in hand '
        '(2026-11-28 유저: 완료와 제출 합침)', () {
      expect(TaskStatus.values, [r, w, s, t]);
      expect(TaskStatus.values.map((v) => v.dbName), [
        'received',
        'in_progress',
        'submitted',
        'retake',
      ]);
      expect(
        [for (final v in TaskStatus.values) v.isOpen],
        [true, true, false, true],
      );
      expect(
        [for (final v in TaskStatus.values) v.isHanded],
        [false, false, true, false],
      );
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
        ..setStatus(ids[1], TaskStatus.inProgress)
        ..setStatus(ids[2], TaskStatus.inProgress)
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
      expect(g.handed, 1);
      expect(g.status, TaskStatus.inProgress);
      expect(g.counts, {TaskStatus.submitted: 1, TaskStatus.inProgress: 3});
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

    test('sorted afresh, groups come in deadline order, no deadline last', () {
      partWithCuts('late', ['C1'], lo, 5);
      store.addPart(ep, 'empty-no-tasks');
      final noDue = store.addPart(ep, 'nodue');
      store
        ..addCut(ep, 'C2', partId: noDue)
        ..addTasksForPart(noDue, lo);
      partWithCuts('early', ['C3'], genga, 1);
      store.clearGroupOrder(); // 「자동 정렬」
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
      // now = Fri 2026-11-27 14:00. These cases count every day unless
      // they say otherwise; the default weekend is tested on its own.
      setUp(() => store.settings.restWeekdays = {});

      test('the default rest days are Saturday and Sunday', () {
        expect(
          CatalogueStore(db).settings.restWeekdays,
          isEmpty, // set in setUp
        );
        db.execute("DELETE FROM settings WHERE key = 'rest_weekdays'");
        expect(store.settings.restWeekdays, {6, 7});
        final part = partWithCuts('B', ['C1', 'C2', 'C3'], lo, 4); // Tue
        final p = store.paceOf(store.partGroups().single)!;
        expect(p.workDays, 3); // Fri, Mon, Tue
        expect(p.perDay, 1);
        expect(part, isPositive);
      });

      test('a trip removes its days; a single day off works too', () {
        partWithCuts('B', ['C1', 'C2', 'C3', 'C4'], lo, 9); // Sun 12/6
        store
          ..addRestDays(DateTime(2026, 11, 30), end: DateTime(2026, 12, 2))
          ..addRestDays(DateTime(2026, 12, 4), title: '병원')
          // A global event that is not a day off counts as a working day.
          ..addEvent(date: DateTime(2026, 12, 3), title: '회의');
        final p = store.paceOf(store.partGroups().single)!;
        // 11/27..12/6 is 10 days; minus 11/30, 12/1, 12/2 and 12/4.
        expect(p.workDays, 6);
        expect(store.restDays().map((d) => d.title), ['', '', '', '병원']);
      });

      test(
        'today off asks nothing today; the rest spreads over the others',
        () {
          partWithCuts('B', ['C1', 'C2', 'C3', 'C4'], lo, 3); // Mon 11/30
          store.addRestDays(DateTime(2026, 11, 27));
          final t = store.today();
          expect(t.entries.single.pace!.workDays, 3); // Sat, Sun, Mon
          expect(t.entries.single.pace!.today, 0);
          expect(t.cutsToday, 0);
        },
      );

      test('a planned start on a day off begins on the next working day', () {
        final part = partWithCuts('B', ['C1', 'C2'], lo, 20);
        store
          ..setPartPlan(
            part,
            lo,
            start: DateTime(2026, 12, 5), // Saturday
            end: DateTime(2026, 12, 8), // Tuesday
          )
          ..settings.restWeekdays = {6, 7};
        final p = store.paceOf(store.partGroups().single)!;
        expect(p.startsLater, isTrue);
        expect(p.workDays, 2); // Mon, Tue
        expect(p.perDay, 1);
        expect(p.today, 0);
      });

      test('an end that falls on a day off counts only working days', () {
        partWithCuts('B', ['C1', 'C2'], lo, 1); // Sat 11/28
        store.settings.restWeekdays = {6, 7};
        final p = store.paceOf(store.partGroups().single)!;
        expect(p.workDays, 1); // today only
        expect(p.today, 2);
      });

      test(
        'only days off left before the end: behind, nothing asked today',
        () {
          final part = partWithCuts('B', ['C1'], lo, 20);
          store
            ..setPartPlan(
              part,
              lo,
              start: DateTime(2026, 12, 12),
              end: DateTime(2026, 12, 13),
            )
            ..settings.restWeekdays = {6, 7};
          final p = store.paceOf(store.partGroups().single)!;
          expect(p.workDays, 0);
          expect(p.behind, isTrue);
          expect(p.today, 0); // the plan has not started
        },
      );

      test('days off: global rest events, removed like any event', () {
        expect(
          () =>
              store.addRestDays(DateTime(2026, 12, 3), end: DateTime(2026, 12)),
          throwsArgumentError,
        );
        final ep = store.addEpisode(store.createWork('W'), '#1');
        expect(
          () => store.addEvent(
            episodeId: ep,
            date: DateTime(2026, 12, 3),
            title: 'x',
            rest: true,
          ),
          throwsArgumentError,
        );
        final id = store.addRestDays(DateTime(2026, 12, 24)).single;
        expect(
          store
              .events(from: DateTime(2026, 12), to: DateTime(2027))[null]!
              .single
              .rest,
          isTrue,
        );
        store.deleteEvent(id);
        expect(store.restDays(), isEmpty);
      });

      test('past days off are skipped when listing from a date', () {
        store
          ..addRestDays(DateTime(2026, 11, 1), end: DateTime(2026, 11, 3))
          ..addRestDays(DateTime(2026, 11, 26), end: DateTime(2026, 11, 28))
          ..addRestDays(DateTime(2026, 12, 25));
        expect(store.restDays(from: now).map((d) => d.date.day), [27, 28, 25]);
      });
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
          ..setStatus(ids[1], TaskStatus.submitted)
          ..requestRetake(ids[0]); // back in hand
        final p = store.paceOf(store.partGroups().single)!;
        expect(p.remaining, 5); // all but the submitted one
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

    group('usual pace and tightness', () {
      test('cuts handed over in 4 weeks ÷ working days, per stage name', () {
        store.settings.restWeekdays = {6, 7};
        final other = store.createWork('마법소녀 리코');
        final otherEp = store.addEpisode(other, '#11');
        final otherLo = store
            .stages(other)
            .firstWhere((s) => s.name == 'LO')
            .id;
        DateTime daysAgo(int n) => now.subtract(Duration(days: n));
        void handed(int stage, int episode, String cut, int ago) {
          final t = store.addTask(stage, cutId: store.addCut(episode, cut));
          CatalogueStore(
            db,
            clock: () => daysAgo(ago),
          ).setStatus(t, TaskStatus.submitted);
        }

        handed(lo, ep, 'C1', 1);
        handed(lo, ep, 'C2', 10);
        handed(otherLo, otherEp, 'C3', 27); // same stage name, other work
        handed(lo, ep, 'C4', 28); // just outside the 4 weeks
        handed(genga, ep, 'C5', 3);
        store.addTask(genga, cutId: store.addCut(ep, 'C6')); // not handed
        store.addRestDays(DateTime(2026, 11, 16), end: DateTime(2026, 11, 20));

        final paces = {for (final u in store.usualPaces()) u.stageName: u};
        // 10/31..11/27 = 28 days, 8 weekend days, 5 days off → 15.
        expect(paces['LO']!.workDays, 15);
        expect(paces['LO']!.cuts, 3);
        expect(paces['LO']!.perDay, closeTo(3 / 15, 1e-9));
        expect(paces['원화']!.cuts, 1);
        expect(paces.keys.toSet(), {'LO', '원화'});
      });

      test('needed vs usual: above is tight, above 1.5× is over', () {
        Pace p(int remaining, int days) => Pace(
          remaining: remaining,
          workDays: days,
          startsLater: false,
          end: now,
        );
        expect(paceLevel(p(4, 2), 2), PaceLevel.ok); // 2 = 2
        expect(paceLevel(p(5, 2), 2), PaceLevel.tight); // 2.5
        expect(paceLevel(p(6, 2), 2), PaceLevel.tight); // 3 = 1.5×
        expect(paceLevel(p(7, 2), 2), PaceLevel.over); // 3.5
        expect(paceLevel(p(3, 0), 2), PaceLevel.over); // behind
        expect(paceLevel(p(3, 2), null), PaceLevel.unknown);
        expect(paceLevel(p(3, 2), 0), PaceLevel.unknown);
        expect(paceLevel(p(0, 2), null), PaceLevel.ok); // nothing left
      });
    });

    test('submitted units hide; submitted cuts still count inside', () {
      final part = partWithCuts('B', ['C1', 'C2'], lo, 3);
      final ids = tasksOf(part, lo);
      store.setStatus(ids[0], TaskStatus.submitted);
      // Part-less: one submitted, one open → the bundle stays with both.
      final a = store.addTask(lo, cutId: store.addCut(ep, 'C8'));
      store
        ..addTask(lo, cutId: store.addCut(ep, 'C9'))
        ..setStatus(a, TaskStatus.submitted);
      // A finished storyboard disappears.
      final conte = store.stages(work).first.id;
      final sb = store.addTask(
        conte,
        storyboardId: store.addStoryboard(ep, '콘티'),
      );
      store.setStatus(sb, TaskStatus.submitted);

      var groups = store.partGroups();
      expect(groups.map((g) => '${g.kind.name} ${g.handed}/${g.total}'), [
        'part 1/2',
        'noPart 1/2',
      ]);
      store.setStatus(ids[1], TaskStatus.submitted);
      groups = store.partGroups();
      expect(groups.map((g) => g.kind), [GroupKind.noPart]);
      expect(store.partGroups(includeDone: true), hasLength(3));
    });

    group('signals', () {
      setUp(() => store.settings.restWeekdays = {});

      PartGroup only() => store.partGroups(includeDone: true).single;
      DueSignal due() => dueSignal(only(), now: now);

      test('the deadline signal looks at dueAt only', () {
        final part = partWithCuts('B', ['C1', 'C2'], lo, 3);
        expect((due() as DueDaysLeft).days, 3);
        // A plan past the deadline does not touch the D signal.
        store.setPartPlan(part, lo, end: now.add(const Duration(days: 9)));
        expect((due() as DueDaysLeft).days, 3);
        store.setPartDue(part, lo, now.subtract(const Duration(days: 2)));
        expect((due() as DueLate).days, 2);
        final ids = tasksOf(part, lo);
        store.setStatusMany(ids, TaskStatus.submitted);
        expect(due(), isA<DueSubmitted>());
      });

      test('no deadline, no D', () {
        store.addTask(lo, cutId: store.addCut(ep, 'C1'));
        expect(due(), isA<DueNone>());
      });

      test(
        'plan signal priority: over > late start > hard > tight > not started',
        () {
          final part = partWithCuts('B', ['C1', 'C2', 'C3', 'C4'], lo, 10);
          PlanSignal plan({double? recent}) => planSignal(
            only(),
            now: now,
            pace: store.paceOf(only()),
            recentPerDay: recent,
          );

          // Not started yet, comfortable.
          store.setPartPlan(
            part,
            lo,
            start: now.add(const Duration(days: 2)),
            end: now.add(const Duration(days: 5)), // 4 cuts / 4 days = 1
          );
          expect(plan(recent: 2), isA<PlanNotStarted>());
          // Tight: needs 1/day, recent 0.8/day.
          expect(plan(recent: 0.8), isA<PlanTight>());
          // Hard: needs 1/day, recent 0.6/day (1.5× = 0.9).
          expect(plan(recent: 0.6), isA<PlanHard>());
          // Late start beats pace: the start has come, nothing begun.
          store.setPartPlan(
            part,
            lo,
            start: now.subtract(const Duration(days: 1)),
            end: now.add(const Duration(days: 3)),
          );
          expect(plan(recent: 0.1), isA<PlanLateStart>());
          // Over beats everything: planned finish after the deadline.
          store.setPartPlan(
            part,
            lo,
            start: now.subtract(const Duration(days: 1)),
            end: now.add(const Duration(days: 12)),
          );
          expect(plan(recent: 0.1), isA<PlanOver>());
          // Once started, a late start is no longer flagged.
          store
            ..setPartPlan(
              part,
              lo,
              start: now,
              end: now.add(const Duration(days: 3)),
            )
            ..setStatus(tasksOf(part, lo).first, TaskStatus.inProgress);
          expect(plan(recent: 5), isA<PlanNone>());
          // Out of the user's hands: nothing to say.
          store.setStatusMany(tasksOf(part, lo), TaskStatus.submitted);
          expect(plan(recent: 0.1), isA<PlanNone>());
        },
      );

      test('today entries and signals() use the recent average per stage', () {
        // Recent LO speed: 2 cuts handed in the last 28 days of 28 → 1/14.
        for (final c in ['H1', 'H2']) {
          final t = store.addTask(lo, cutId: store.addCut(ep, c));
          CatalogueStore(
            db,
            clock: () => now.subtract(const Duration(days: 3)),
          ).setStatus(t, TaskStatus.submitted);
        }
        partWithCuts('B', ['C1', 'C2'], lo, 1); // needs 1/day → hard
        final entry = store.today().entries.single;
        expect(entry.group.partLabel, 'B');
        expect(entry.plan, isA<PlanHard>());
        expect((entry.due as DueDaysLeft).days, 1);
        final sig = store.signals()[entry.group.key]!;
        expect(sig.plan, isA<PlanHard>());
        expect(sig.pace!.perDay, 1);
      });

      test('recent and overall averages; the recent window is a setting', () {
        void handed(String cut, int daysAgo) {
          final t = store.addTask(lo, cutId: store.addCut(ep, cut));
          CatalogueStore(
            db,
            clock: () => now.subtract(Duration(days: daysAgo)),
          ).setStatus(t, TaskStatus.submitted);
        }

        handed('H1', 1);
        handed('H2', 5);
        handed('H3', 59); // first ever: 60 days counted to today
        var lo_ = store.stagePaces().single;
        expect(lo_.stageName, 'LO');
        expect(lo_.recent.cuts, 2);
        expect(lo_.recent.workDays, 28);
        expect(lo_.overall.cuts, 3);
        expect(lo_.overall.workDays, 60);
        store.settings.recentPaceDays = 7;
        lo_ = store.stagePaces().single;
        expect(lo_.recent.workDays, 7);
        expect(lo_.recent.cuts, 2);
        expect(() => store.settings.recentPaceDays = 0, throwsRangeError);
      });
    });

    group('kickoff and order', () {
      test('kickoff: part default, cut override, shown with its source', () {
        final part = partWithCuts('B', ['C1', 'C2'], lo, 10);
        final ids = tasksOf(part, lo);
        final kick = DateTime(2026, 11, 20);
        store.setPartKickoff(part, lo, kick);
        var g = store.partGroups().single;
        expect(g.kickoffAt, kick.toUtc());
        expect(g.tasks.every((t) => t.kickoffFromPart), isTrue);
        final own = DateTime(2026, 11, 22);
        store.setTaskKickoff(ids[1], own);
        g = store.partGroups().single;
        expect(g.tasks[1].kickoffAt, own.toUtc());
        expect(g.tasks[1].kickoffFromPart, isFalse);
        expect(g.tasks[0].kickoffAt, kick.toUtc());
        store.setPartKickoff(part, lo, null);
        expect(store.partGroups().single.kickoffAt, isNull);
      });

      test('without a plan, the pace counts from the kickoff', () {
        store.settings.restWeekdays = {};
        final part = partWithCuts('B', ['C1', 'C2', 'C3'], lo, 2);
        // Kickoff defaulted to today: 3 cuts over today .. +2 days.
        expect(store.paceOf(store.partGroups().single)!.perDay, 1);
        // Kickoff tomorrow: 3 cuts over 2 days, nothing asked today.
        store.setPartKickoff(part, lo, now.add(const Duration(days: 1)));
        var pace = store.paceOf(store.partGroups().single)!;
        expect(pace.perDay, 1.5);
        expect(pace.startsLater, isTrue);
        expect(pace.today, 0);
        // A planned start wins over the kickoff; so does a planned end
        // over the deadline.
        store.setPartPlan(
          part,
          lo,
          start: now,
          end: now.add(const Duration(days: 5)),
        );
        pace = store.paceOf(store.partGroups().single)!;
        expect(pace.startsLater, isFalse);
        expect(pace.workDays, 6);
        // D stays on the deadline whatever the kickoff.
        expect((store.signals().values.single.due as DueDaysLeft).days, 2);
      });

      test('the kickoff defaults to the day the work was entered', () {
        final part = partWithCuts('B', ['C1', 'C2'], lo, 9);
        final today = DateTime(now.year, now.month, now.day).toUtc();
        var g = store.partGroups().single;
        expect(g.kickoffAt, today);
        expect(g.tasks.every((t) => t.kickoffFromPart), isTrue);
        // A part that already has one keeps it.
        final earlier = DateTime(2026, 11, 1);
        store.setPartKickoff(part, genga, earlier);
        store.addTasksForPart(part, genga);
        g = store.partGroups().firstWhere((g) => g.stageId == genga);
        expect(g.kickoffAt, earlier.toUtc());
        // A cut outside any part gets its own.
        final solo = store.addTask(lo, cutId: store.addCut(ep, 'C9'));
        final row = store.taskRows().firstWhere((t) => t.id == solo);
        expect((row.kickoffAt, row.kickoffFromPart), (today, false));
      });

      test('a dropped bar writes kickoff and deadline together', () {
        final part = partWithCuts('B', ['C1'], lo, 10);
        final k = DateTime(2026, 12, 1);
        final d = DateTime(2026, 12, 9);
        store.setPartSchedule(part, lo, kickoffAt: k, dueAt: d);
        var g = store.partGroups().single;
        expect((g.kickoffAt, g.dueAt), (k.toUtc(), d.toUtc()));
        expect(
          () => store.setPartSchedule(part, lo, kickoffAt: d, dueAt: k),
          throwsArgumentError,
        );
        g = store.partGroups().single;
        expect((g.kickoffAt, g.dueAt), (k.toUtc(), d.toUtc()));
        store.setPartSchedule(part, lo, kickoffAt: null, dueAt: null);
        g = store.partGroups().single;
        expect((g.kickoffAt, g.dueAt), (null, null));
      });

      test('part-less units: earliest kickoff, a range label', () {
        for (final c in ['C100', 'C101', 'C102', 'C103', 'C105']) {
          store.addTask(lo, cutId: store.addCut(ep, c));
        }
        final g = store.partGroups().single;
        expect(g.kind, GroupKind.noPart);
        expect(g.cutsLabel, 'C100~C103, C105');
        store.setTaskKickoff(g.tasks[2].id, DateTime(2026, 11, 3));
        store.setTaskKickoff(g.tasks[0].id, DateTime(2026, 11, 5));
        expect(
          store.partGroups().single.kickoffAt,
          DateTime(2026, 11, 3).toUtc(),
        );
      });

      test('changing a deadline keeps the rows where they are', () {
        final a = partWithCuts('A', ['C1'], lo, 1);
        partWithCuts('B', ['C2'], lo, 2);
        List<String?> labels() =>
            store.partGroups().map((g) => g.partLabel).toList();
        expect(labels(), ['A', 'B']);
        store.setPartDue(a, lo, now.add(const Duration(days: 9)));
        expect(labels(), ['A', 'B']);
        store.clearGroupOrder(); // 「자동 정렬」
        expect(labels(), ['B', 'A']);
      });

      test('drag order wins; new units follow by deadline; auto clears', () {
        partWithCuts('A', ['C1'], lo, 1);
        partWithCuts('B', ['C2'], lo, 2);
        partWithCuts('C', ['C3'], lo, 3);
        store.clearGroupOrder();
        List<String?> labels() =>
            store.partGroups().map((g) => g.partLabel).toList();
        expect(labels(), ['A', 'B', 'C']);
        expect(store.hasGroupOrder, isFalse);

        final keys = {for (final g in store.partGroups()) g.partLabel: g.key};
        store.setGroupOrder([keys['C']!, keys['A']!, keys['B']!]);
        expect(labels(), ['C', 'A', 'B']);
        expect(store.hasGroupOrder, isTrue);

        // A new unit, even with an earlier deadline, comes after them.
        partWithCuts('D', ['C4'], lo, 0);
        partWithCuts('E', ['C5'], lo, 5);
        expect(labels(), ['C', 'A', 'B', 'D', 'E']);

        store.clearGroupOrder();
        expect(labels(), ['D', 'A', 'B', 'C', 'E']);
        expect(store.hasGroupOrder, isFalse);
      });
    });
  });
}
