import 'dart:io';

import 'package:anisched/src/models/work_interval.dart';
import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 27, 9);
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = t0);

  group('WorkInterval', () {
    test('a running interval counts up to now', () {
      final i = WorkInterval(id: 1, start: t0);
      expect(
        i.elapsed(t0.add(const Duration(minutes: 5))),
        const Duration(minutes: 5),
      );
    });

    test('a stopped interval ignores now', () {
      final i = WorkInterval(
        id: 1,
        start: t0,
        stop: t0.add(const Duration(minutes: 30)),
      );
      expect(
        i.elapsed(t0.add(const Duration(days: 3))),
        const Duration(minutes: 30),
      );
    });

    test('elapsed is never negative', () {
      final i = WorkInterval(id: 1, start: t0);
      expect(i.elapsed(t0.subtract(const Duration(hours: 1))), Duration.zero);
    });

    test('clipping splits work across midnight', () {
      final i = WorkInterval(
        id: 1,
        start: DateTime.utc(2026, 11, 27, 23),
        stop: DateTime.utc(2026, 11, 28, 2),
      );
      final midnight = DateTime.utc(2026, 11, 28);
      expect(
        i.elapsedWithin(DateTime.utc(2026, 11, 27), midnight, midnight),
        const Duration(hours: 1),
      );
      expect(
        i.elapsedWithin(midnight, DateTime.utc(2026, 11, 29), midnight),
        const Duration(hours: 2),
      );
    });

    test('totalElapsed sums intervals', () {
      final list = [
        WorkInterval(id: 1, start: t0, stop: t0.add(const Duration(hours: 1))),
        WorkInterval(id: 2, start: t0.add(const Duration(hours: 2))),
      ];
      expect(
        totalElapsed(list, t0.add(const Duration(hours: 3))),
        const Duration(hours: 2),
      );
    });
  });

  group('WorkTimerStore', () {
    test('start then stop records the interval', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock);
      store.start();
      now = t0.add(const Duration(minutes: 42));
      final stopped = store.stop()!;
      expect(stopped.elapsed(now), const Duration(minutes: 42));
      expect(store.running(), isNull);
    });

    test('a second start while running is refused', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock)..start();
      expect(store.start, throwsA(isA<TimerAlreadyRunningException>()));
    });

    test('stop with nothing running returns null', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      expect(WorkTimerStore(db, clock: clock).stop(), isNull);
    });

    test('a running timer survives the app being killed and relaunched', () {
      final dir = Directory.systemTemp.createTempSync('anisched');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.db';

      final first = openAppDatabase(path);
      WorkTimerStore(first, clock: clock).start();
      first.close(); // the process dies; nothing else is written

      now = t0.add(const Duration(hours: 2, minutes: 15));
      final second = openAppDatabase(path);
      addTearDown(second.close);
      final store = WorkTimerStore(second, clock: clock);
      final open = store.running()!;
      expect(open.start, t0);
      expect(open.elapsed(now), const Duration(hours: 2, minutes: 15));

      now = now.add(const Duration(minutes: 45));
      expect(store.stop()!.elapsed(now), const Duration(hours: 3));
    });

    test('a clock that went backwards stops at zero length', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock)..start();
      now = t0.subtract(const Duration(minutes: 10));
      final stopped = store.stop()!;
      expect(stopped.stop, t0);
      expect(stopped.elapsed(now), Duration.zero);
    });

    test('workedBetween clips to the range and includes a running timer', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock);
      now = DateTime.utc(2026, 11, 27, 22);
      store.start();
      now = DateTime.utc(2026, 11, 28, 1);
      store.stop();
      now = DateTime.utc(2026, 11, 28, 3);
      store.start();
      now = DateTime.utc(2026, 11, 28, 4);

      final day27 = store.workedBetween(
        DateTime.utc(2026, 11, 27),
        DateTime.utc(2026, 11, 28),
      );
      final day28 = store.workedBetween(
        DateTime.utc(2026, 11, 28),
        DateTime.utc(2026, 11, 29),
      );
      expect(day27, const Duration(hours: 2));
      expect(day28, const Duration(hours: 2));
    });

    test('time can be recorded on a task', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      db
        ..execute("INSERT INTO works (title, created_at) VALUES ('W', 0);")
        ..execute(
          "INSERT INTO work_stages (work_id, name, position) VALUES (1, 'LO', 0);",
        )
        ..execute(
          "INSERT INTO episodes (work_id, number, sort_key) VALUES (1, '1', '1');",
        )
        ..execute(
          "INSERT INTO cuts (episode_id, number, sort_key) VALUES (1, 'C1', 'c1');",
        )
        ..execute('INSERT INTO tasks (stage_id, cut_id) VALUES (1, 1);');
      final store = WorkTimerStore(db, clock: clock);
      expect(store.start(taskId: 1).taskId, 1);
      now = t0.add(const Duration(minutes: 20));
      expect(store.stop()!.taskId, 1);
      store.start(); // untracked time does not count toward the task
      now = t0.add(const Duration(hours: 1));
      expect(store.workedOn(1), const Duration(minutes: 20));
    });
  });

  group('week hours and day intervals', () {
    test('per working day of the week, cut at the day start', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      // now: Friday 2026-11-27 14:00 local.
      var clockNow = DateTime(2026, 11, 27, 14);
      final store = CatalogueStore(db, clock: () => clockNow);
      final timer = WorkTimerStore(db, clock: () => clockNow.toUtc());
      void work(DateTime from, Duration d) {
        clockNow = from;
        timer.start();
        clockNow = from.add(d);
        timer.stop();
      }

      work(DateTime(2026, 11, 23, 10), const Duration(hours: 2)); // Mon
      work(DateTime(2026, 11, 25, 23), const Duration(hours: 3)); // Wed→Thu
      work(DateTime(2026, 11, 22, 10), const Duration(hours: 9)); // last Sun
      clockNow = DateTime(2026, 11, 27, 13);
      timer.start(); // running since 13:00
      clockNow = DateTime(2026, 11, 27, 14);

      final week = store.weekHours();
      expect(week.first.day, DateTime(2026, 11, 23));
      expect(week.map((d) => d.worked.inMinutes), [
        120, 0, 60, 120, 60, 0, 0, //
      ]);

      // With days starting at 05:00, Wed 23:00–Thu 02:00 is all Wednesday.
      store.settings.dayStartMinutes = 300;
      expect(store.weekHours().map((d) => d.worked.inMinutes), [
        120, 0, 180, 0, 60, 0, 0, //
      ]);

      // Weeks can start on Sunday.
      store.settings
        ..dayStartMinutes = 0
        ..weekStart = DateTime.sunday;
      final sunWeek = store.weekHours();
      expect(sunWeek.first.day, DateTime(2026, 11, 22));
      expect(sunWeek.first.worked, const Duration(hours: 9));

      final today = store.dayIntervals();
      expect(today, hasLength(1));
      expect(today.single.running, isTrue);
      expect(today.single.end.difference(today.single.start).inMinutes, 60);
      final wed = store.dayIntervals(day: DateTime(2026, 11, 25, 12));
      expect(wed.single.end.difference(wed.single.start).inMinutes, 60);
    });
  });

  group('play/pause on tasks', () {
    late Database db;
    late CatalogueStore store;
    late WorkTimerStore timer;
    var now = DateTime(2026, 11, 2, 10);
    setUp(() {
      now = DateTime(2026, 11, 2, 10);
      db = openAppDatabase(':memory:');
      store = CatalogueStore(db, clock: () => now.toUtc());
      timer = WorkTimerStore(db, clock: () => now.toUtc());
    });
    tearDown(() => db.close());
    int stage(int w, String name) =>
        store.stages(w).firstWhere((s) => s.name == name).id;
    test('play/pause toggles; another task takes the timer over', () {
      final w = store.createWork('W');
      final r = store.addEpisodeWithCuts(w, '#1', 'C001~C002');
      final a = store.addTask(stage(w, '원화'), cutId: r.cutIds[0]);
      final b = store.addTask(stage(w, '원화'), cutId: r.cutIds[1]);

      expect(timer.toggle(taskId: a)!.taskId, a);
      now = now.add(const Duration(minutes: 30));
      expect(timer.toggle(taskId: a), isNull); // paused
      now = now.add(const Duration(minutes: 10));
      timer.toggle(taskId: a);
      now = now.add(const Duration(minutes: 5));
      expect(timer.toggle(taskId: b)!.taskId, b); // moved
      now = now.add(const Duration(minutes: 20));

      expect(store.workedOn([a, b]), {
        a: const Duration(minutes: 35),
        b: const Duration(minutes: 20), // running, counted to now
      });
      expect(store.runningTimer()!.taskId, b);
    });

    test('picking a cut: the setting alone decides', () {
      final w = store.createWork('W');
      final r = store.addEpisodeWithCuts(w, '#1', 'C001~C002');
      final a = store.addTask(stage(w, '원화'), cutId: r.cutIds[0]);
      final b = store.addTask(stage(w, '원화'), cutId: r.cutIds[1]);
      expect(store.settings.timerAutoStart, isFalse);

      // Off (default): the picked cut comes up paused, running or not.
      timer.start(taskId: a);
      expect(timer.selectionChanged(b, autoStart: false), isNull);
      expect(timer.running(), isNull);
      expect(timer.selectionChanged(a, autoStart: false), isNull);
      expect(timer.running(), isNull);

      // On: the picked cut runs, from paused or from another cut.
      store.settings.timerAutoStart = true;
      final auto = store.settings.timerAutoStart;
      expect(timer.selectionChanged(a, autoStart: auto)!.taskId, a);
      expect(timer.selectionChanged(b, autoStart: auto)!.taskId, b);
      final runningOnB = timer.running()!.id;
      // Picking the running cut again keeps the same stretch.
      expect(timer.selectionChanged(b, autoStart: auto)!.id, runningOnB);
      expect(timer.selectionChanged(null, autoStart: auto), isNull);
      expect(timer.running(), isNull);
    });

    test('submitting pauses a running timer and keeps its cut', () {
      final w = store.createWork('W');
      final r = store.addEpisodeWithCuts(w, '#1', 'C001');
      final a = store.addTask(stage(w, '원화'), cutId: r.cutIds[0]);
      timer.start(taskId: a);
      now = now.add(const Duration(minutes: 15));
      store.setStatus(a, TaskStatus.submitted);
      expect(timer.running(), isNull);
      now = now.add(const Duration(hours: 1));
      expect(store.workedOn([a]), {a: const Duration(minutes: 15)});
      expect(store.intervalsOf(a).single.taskId, a);
    });

    test('the timer\'s target survives a reopen; a gone one reads null', () {
      final dir = Directory.systemTemp.createTempSync('anisched-target');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.db';
      var file = openAppDatabase(path);
      var s = CatalogueStore(file);
      final w = s.createWork('W');
      final r = s.addEpisodeWithCuts(w, '#1', 'C001~C003');
      final key = s.stages(w).firstWhere((x) => x.name == '원화').id;
      final a = s.addTask(key, cutId: r.cutIds[0]);
      final b = s.addTask(key, cutId: r.cutIds[1]);
      final c = s.addTask(key, cutId: r.cutIds[2]);
      expect(s.timerTarget(), isNull);
      s.setTimerTarget(a);
      file.close();
      file = openAppDatabase(path);
      s = CatalogueStore(file);
      expect(s.timerTarget(), a);
      s
        ..archive(ArchiveKind.task, a)
        ..setTimerTarget(a);
      expect(s.timerTarget(), isNull); // deleted
      s
        ..setStatus(b, TaskStatus.submitted)
        ..setTimerTarget(b);
      expect(s.timerTarget(), isNull); // submitted
      s
        ..handOff([c])
        ..setTimerTarget(c);
      expect(s.timerTarget(), isNull); // handed off
      s.setTimerTarget(null);
      expect(s.settings.timerTargetId, isNull);
      file.close();
    });

    test('the cuts beside a task: same episode, done ones too', () {
      final w = store.createWork('W');
      final r1 = store.addEpisodeWithCuts(w, '#1', 'C001~C003');
      final r2 = store.addEpisodeWithCuts(w, '#2', 'C001');
      final key = stage(w, '원화');
      final a = store.addTask(key, cutId: r1.cutIds[0]);
      final b = store.addTask(key, cutId: r1.cutIds[1]);
      final c = store.addTask(key, cutId: r1.cutIds[2]);
      store
        ..addTask(key, cutId: r2.cutIds[0])
        ..setStatus(c, TaskStatus.inProgress);
      expect(store.tasksBeside(a).map((t) => t.id), [b, c]);
      expect(store.tasksBeside(999), isEmpty);
    });
  });

  group('editing the record by hand', () {
    late Database db;
    late CatalogueStore store;
    late WorkTimerStore timer;
    late int task;
    setUp(() {
      now = t0;
      db = openAppDatabase(':memory:');
      store = CatalogueStore(db, clock: clock);
      timer = WorkTimerStore(db, clock: clock);
      final w = store.createWork('W');
      final r = store.addEpisodeWithCuts(w, '#1', 'C001');
      task = store.addTask(
        store.stages(w).firstWhere((s) => s.name == '원화').id,
        cutId: r.cutIds[0],
      );
    });
    tearDown(() => db.close());
    DateTime at(int h) => t0.subtract(Duration(hours: 10 - h));

    test('left running overnight: cut the stop back', () {
      timer.start(taskId: task);
      now = t0.add(const Duration(hours: 9));
      timer.editInterval(
        timer.running()!.id,
        stop: t0.add(const Duration(hours: 2)),
      );
      expect(timer.running(), isNull);
      expect(store.workedOn([task]), {task: const Duration(hours: 2)});
    });

    test('add, move and delete stretches; listed oldest first', () {
      final late = timer.addInterval(taskId: task, start: at(5), stop: at(6));
      final early = timer.addInterval(taskId: task, start: at(1), stop: at(2));
      expect(store.intervalsOf(task).map((i) => i.id), [early.id, late.id]);
      timer.editInterval(early.id, start: at(0));
      expect(store.workedOn([task]), {task: const Duration(hours: 3)});
      timer.deleteInterval(late.id);
      expect(store.intervalsOf(task).map((i) => i.id), [early.id]);
    });

    test('overlaps are refused; touching ends are fine', () {
      final a = timer.addInterval(taskId: task, start: at(1), stop: at(3));
      expect(
        () => timer.addInterval(taskId: task, start: at(2), stop: at(4)),
        throwsA(
          isA<IntervalOverlapException>().having(
            (e) => e.otherId,
            'otherId',
            a.id,
          ),
        ),
      );
      final b = timer.addInterval(start: at(3), stop: at(4)); // no task too
      expect(
        () => timer.editInterval(b.id, start: at(2)),
        throwsA(isA<IntervalOverlapException>()),
      );
      // A running stretch reaches to now.
      timer.start(taskId: task);
      now = t0.add(const Duration(hours: 1));
      expect(
        () => timer.addInterval(
          start: t0.add(const Duration(minutes: 30)),
          stop: now,
        ),
        throwsA(isA<IntervalOverlapException>()),
      );
    });

    test('backwards or future stretches are refused', () {
      expect(
        () => timer.addInterval(start: at(3), stop: at(2)),
        throwsArgumentError,
      );
      expect(
        () => timer.addInterval(
          start: at(9),
          stop: t0.add(const Duration(minutes: 1)),
        ),
        throwsArgumentError,
      );
      expect(() => timer.editInterval(42, stop: at(1)), throwsStateError);
      expect(store.intervalsOf(task), isEmpty);
    });
  });
}
