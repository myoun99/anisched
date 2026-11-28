import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late CatalogueStore store;
  late WorkTimerStore timer;
  var now = DateTime(2026, 11, 2, 10); // Monday, local

  setUp(() {
    now = DateTime(2026, 11, 2, 10);
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now.toUtc());
    timer = WorkTimerStore(db, clock: () => now.toUtc());
  });
  tearDown(() => db.close());

  int stage(int w, String name) =>
      store.stages(w).firstWhere((s) => s.name == name).id;

  test('a retake hand-in keeps the first hand-in date', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C001');
    final t = store.addTask(stage(w, '원화'), cutId: r.cutIds[0]);
    store.setStatus(t, TaskStatus.submitted);
    final first = now;
    now = now.add(const Duration(days: 3));
    store.requestRetake(t);
    store.setStatus(t, TaskStatus.submitted);
    final row = db.select('SELECT submitted_at FROM tasks WHERE id = ?', [t]);
    expect(row.first.columnAt(0), first.toUtc().millisecondsSinceEpoch);
    final take = db.select(
      'SELECT submitted_at FROM retakes WHERE task_id = ?',
      [t],
    );
    expect(take.first.columnAt(0), now.toUtc().millisecondsSinceEpoch);
  });

  test('statistics for a range', () {
    final client = store.addClient('Studio');
    final w = store.createWork('W', clientId: client);
    final r = store.addEpisodeWithCuts(w, '#1', 'C001~C004', partLabel: 'A');
    final genga = stage(w, '원화');
    store.setEpisodeRate(r.episodeId, genga, const Rate(RateUnit.fixed, 4000));
    final tasks = [
      for (final c in r.cutIds)
        store.addTask(genga, cutId: c, dueAt: DateTime(2026, 11, 4, 18)),
    ];
    store.setPartPlan(
      r.partId!,
      genga,
      start: DateTime(2026, 11, 2),
      end: DateTime(2026, 11, 6),
    );

    // Mon 10:00–12:00 on cut 1, handed Mon; Tue 14:00–15:00 on cut 2,
    // handed Wed (on time); cut 3 handed Fri (2 days late) after a retake.
    // Handing in marks done. Cut 4 is finished Thu but not handed in.
    timer.start(taskId: tasks[0]);
    now = DateTime(2026, 11, 2, 12);
    timer.stop();
    store.setStatus(tasks[0], TaskStatus.submitted);
    now = DateTime(2026, 11, 3, 14);
    timer.start(taskId: tasks[1]);
    now = DateTime(2026, 11, 3, 15);
    timer.stop();
    now = DateTime(2026, 11, 4, 9);
    store.setStatus(tasks[1], TaskStatus.submitted);
    now = DateTime(2026, 11, 5, 9);
    store.setStatus(tasks[3], TaskStatus.done);
    now = DateTime(2026, 11, 6, 9);
    store.setStatus(tasks[2], TaskStatus.submitted);
    store.requestRetake(tasks[2]);
    store.setStatus(tasks[2], TaskStatus.submitted);
    now = DateTime(2026, 11, 9, 9);

    final s = store.stats(
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 9),
      bucket: StatsBucket.day,
    );
    expect(s.total.handed, 3);
    expect(s.total.done, 4);
    expect(s.total.worked, const Duration(hours: 3));
    expect(s.total.perCut, const Duration(minutes: 90));
    expect(s.total.earned, {'JPY': 16000});
    expect(s.hourly['JPY'], closeTo(8000 / 3, 0.001)); // timed cuts only
    expect(s.periods, hasLength(7));
    expect([for (final p in s.periods) p.handed], [1, 0, 1, 0, 1, 0, 0]);
    expect(s.periods[0].worked, const Duration(hours: 2));
    expect(s.periods[0].earned, {'JPY': 4000}); // done when handed Mon
    expect(s.periods[3].earned, {'JPY': 4000}); // cut 4, done Thu
    expect(s.lateness, {-2: 1, 0: 1, 2: 1});
    expect(s.onTime, 2);
    expect(s.late, 1);
    expect(s.takes, {1: 2, 2: 1});
    expect(s.total.retakeRate, closeTo(1 / 3, 0.001));
    expect(s.heatmap[0][10], const Duration(hours: 1)); // Mon 10h
    expect(s.heatmap[0][11], const Duration(hours: 1));
    expect(s.heatmap[1][14], const Duration(hours: 1)); // Tue 14h
    expect(s.days.first, (day: DateTime(2026, 11, 2), worked: 1, planned: 1));
    expect(s.days[5].planned, 0); // Sat, after the plan
    expect(s.lanes, 2);
    expect(s.stages.single.label, '원화');
    expect(s.works.single.earned, {'JPY': 16000});
    expect(s.clients.single.label, 'Studio');
  });

  test('adherence uses the deadline at hand-in; previous range; progress', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C001~C003');
    final genga = stage(w, '원화');
    final due = DateTime(2026, 11, 4, 18);
    final a = store.addTask(genga, cutId: r.cutIds[0], dueAt: due);
    final b = store.addTask(genga, cutId: r.cutIds[1], dueAt: due);
    store.addTask(genga, cutId: r.cutIds[2], dueAt: due);

    now = DateTime(2026, 11, 4, 20); // same day, two hours late
    store.setStatus(a, TaskStatus.submitted);
    store.setTaskDue(a, DateTime(2026, 11, 10)); // moved afterwards
    now = DateTime(2026, 10, 28, 9); // the week before
    store.setStatus(b, TaskStatus.submitted);
    now = DateTime(2026, 11, 9, 9);

    final s = store.stats(
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 9),
      bucket: StatsBucket.day,
    );
    expect(s.lateness, {1: 1});
    expect(s.total.handed, 1);
    expect(s.previous!.total.handed, 1);
    expect(s.previous!.from, DateTime(2026, 10, 26));
    expect(s.previous!.previous, isNull);
    expect(s.works.single.cuts, 3);
    expect(s.works.single.finished, 2);
    expect(s.works.single.progress, closeTo(2 / 3, 0.001));
    expect(s.stagePaces, isNotEmpty);
  });

  test('weeks start on the week-start setting', () {
    store.settings.weekStart = DateTime.sunday;
    final s = store.stats(
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 30),
      bucket: StatsBucket.week,
    );
    expect(s.periods.first.start, DateTime(2026, 11, 1));
    expect(s.periods.first.start.weekday, DateTime.sunday);
    final m = store.stats(
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 30),
      bucket: StatsBucket.month,
    );
    expect(m.periods.single.start, DateTime(2026, 11));
  });

  test('the hourly rate leaves out paid work with no time on it', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C001~C002');
    final genga = stage(w, '원화');
    store.setEpisodeRate(r.episodeId, genga, const Rate(RateUnit.fixed, 3000));
    final timed = store.addTask(genga, cutId: r.cutIds[0]);
    final untimed = store.addTask(genga, cutId: r.cutIds[1]);
    timer.start(taskId: timed);
    now = DateTime(2026, 11, 2, 11);
    timer.stop();
    store
      ..setStatus(timed, TaskStatus.done)
      ..setStatus(untimed, TaskStatus.done);
    final s = store.stats(
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 3),
    );
    expect(s.total.earned, {'JPY': 6000});
    expect(s.hourly['JPY'], 3000);
  });

  test('submitting work not done marks it done too; done stays first', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C001~C002');
    final a = store.addTask(stage(w, '원화'), cutId: r.cutIds[0]);
    final b = store.addTask(stage(w, '원화'), cutId: r.cutIds[1]);
    int? col(int id, String c) =>
        db.select('SELECT $c FROM tasks WHERE id = ?', [id]).first.columnAt(0)
            as int?;
    store.setStatus(a, TaskStatus.submitted);
    expect(col(a, 'done_at'), col(a, 'submitted_at'));
    final finished = now.toUtc().millisecondsSinceEpoch;
    store.setStatus(b, TaskStatus.done);
    now = now.add(const Duration(days: 2));
    store.setStatus(b, TaskStatus.submitted);
    expect(col(b, 'done_at'), finished);
    expect(col(b, 'submitted_at'), isNot(finished));
  });
}
