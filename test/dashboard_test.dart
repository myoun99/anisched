import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard tab (유저 2026-11-28): one read whose figures are the
/// today list's, the signals' and the statistics'.
void main() {
  late AppDatabase db;
  late CatalogueStore store;
  var now = DateTime(2026, 11, 28, 14); // a Saturday
  late int lo;
  late int partA;
  late int partB;
  late int partC;
  late List<int> a;
  late List<int> b;

  void interval(DateTime start, Duration length, int task) => db.execute(
    'INSERT INTO work_intervals (started_at, stopped_at, task_id) '
    'VALUES (?, ?, ?);',
    [
      start.millisecondsSinceEpoch,
      start.add(length).millisecondsSinceEpoch,
      task,
    ],
  );

  setUp(() {
    now = DateTime(2026, 11, 28, 14);
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now);
    final work = store.createWork('작품');
    lo = store.stages(work).firstWhere((s) => s.name == 'LO').id;
    final ep = store.addEpisode(work, '1');
    store.setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 1000));
    partA = store.addPart(ep, 'A');
    partB = store.addPart(ep, 'B');
    partC = store.addPart(ep, 'C');
    store
      ..addCuts(ep, ['1', '2', '3', '4'], partId: partA)
      ..addCuts(ep, ['5', '6'], partId: partB)
      ..addCuts(ep, ['7'], partId: partC);
    a = store.addTasksForPart(partA, lo);
    b = store.addTasksForPart(partB, lo);
    store
      ..addTasksForPart(partC, lo)
      ..setPartDue(partA, lo, DateTime(2026, 11, 30)) // D-2
      ..setPartDue(partB, lo, DateTime(2026, 12, 20)) // outside the week
      ..setPartDue(partC, lo, DateTime(2026, 11, 25)); // late

    // Last week: one cut of B handed in, an hour on it.
    now = DateTime(2026, 11, 18, 15);
    store.setStatus(b[0], TaskStatus.submitted);
    interval(DateTime(2026, 11, 18, 10), const Duration(hours: 1), b[0]);
    // Today: one cut of A handed in, one in retake, two hours.
    now = DateTime(2026, 11, 28, 14);
    store
      ..setStatus(a[0], TaskStatus.submitted)
      ..setStatus(a[1], TaskStatus.retake);
    interval(DateTime(2026, 11, 28, 9), const Duration(hours: 2), a[0]);

    store
      ..addEvent(date: DateTime(2026, 11, 28), timeMinutes: 600, title: '회의')
      ..addEvent(episodeId: ep, date: DateTime(2026, 11, 29), title: '아후레코')
      ..addEvent(
        card: 'part:$partA:$lo',
        date: DateTime(2026, 11, 29),
        title: '체크',
      )
      ..addEvent(date: DateTime(2026, 12, 1), title: '나중');
  });

  tearDown(() => db.close());

  test('each part of the dashboard is the figure its own view shows', () {
    final d = store.dashboard();
    final today = store.today();
    final signals = store.signals();
    final day = DateTime(2026, 11, 28);

    // Today.
    expect(d.day, day);
    expect(d.today.cutsToday, today.cutsToday);
    expect(d.today.entries.map((e) => e.group.key), [
      for (final e in today.entries) e.group.key,
    ]);
    final todayStats = store.stats(from: day, to: DateTime(2026, 11, 29)).total;
    expect((d.cutsHandedToday, d.workedToday), (1, const Duration(hours: 2)));
    expect(d.cutsHandedToday, todayStats.handed);
    expect(d.running, isNull);

    // Due soon: the late card first, then D-2; B is outside the window.
    expect(d.dueSoon.map((x) => (x.group.partId, x.daysLeft, x.late)), [
      (partC, -3, true),
      (partA, 2, false),
    ]);
    for (final x in d.dueSoon) {
      final pace = signals[x.group.key]!.pace!;
      expect((x.remaining, x.perDay), (pace.remaining, pace.today));
    }
    expect(d.dueSoon.last.remaining, 3); // 2 received + 1 retake

    // Today and tomorrow, all kinds, all-day first.
    expect(d.events.map((e) => e.title), ['회의', '아후레코', '체크']);
    expect(d.holidays, store.holidays(from: day, to: DateTime(2026, 11, 30)));

    // Attention.
    expect(d.late, today.late);
    expect(d.retakeCuts, 1);
    expect(d.retakeCards, ['part:$partA:$lo']);
    expect(d.waiting, store.holding().waiting);

    // This week (Monday start) against the last.
    expect(d.weekFrom, DateTime(2026, 11, 23));
    final week = store.stats(
      from: DateTime(2026, 11, 23),
      to: DateTime(2026, 11, 30),
    );
    expect(
      (d.thisWeek.handed, d.thisWeek.worked),
      (week.total.handed, week.total.worked),
    );
    expect(d.thisWeek.earned, week.total.earned);
    final last = week.previous!.total;
    expect((d.lastWeek.handed, d.lastWeek.worked), (last.handed, last.worked));
    expect(d.lastWeek.earned, last.earned);
    expect((d.thisWeek.handed, d.lastWeek.handed), (1, 1));
    expect(d.lastWeek.worked, const Duration(hours: 1));
  });

  test('a late card with nothing left to work on is neither due soon nor '
      'late (유저 2026-11-28)', () {
    final before = store.dashboard();
    // Every cut of the late card C done, none submitted: the card stays
    // open, with 0 cuts to work on.
    for (final t
        in store.partGroups().firstWhere((g) => g.partId == partC).tasks) {
      store.setStatus(t.id, TaskStatus.done);
    }
    final d = store.dashboard();
    expect(d.dueSoon.map((x) => x.group.partId), [partA]);
    expect(d.late, before.late - 1);
    expect(store.today().late, d.late);
    // A card that still has work is late as before.
    store.setStatus(b[1], TaskStatus.retake);
    expect(store.dashboard().late, d.late);
  });

  test('the reader answers the same in one round trip', () async {
    final d = await SyncCatalogueReader(store).dashboard(dueLimit: 1);
    expect(d.dueSoon.single.group.partId, partC);
    expect(d.today.cutsToday, store.today().cutsToday);
  });

  test('bench: 10,000 cuts', () {
    final work = store.createWork('극장판');
    final genga = store.stages(work).firstWhere((s) => s.name == '원화').id;
    final r = store.addEpisodeWithCuts(
      work,
      '극장판',
      '1~3000, 3001~6000, 6001~9000, 9001~10000',
      partLabel: 'All',
    );
    store
      ..addTasksForPart(r.partId!, genga)
      ..setPartDue(r.partId!, genga, DateTime(2026, 12, 2));
    final sw = Stopwatch()..start();
    final d = store.dashboard();
    sw.stop();
    expect(d.dueSoon.map((x) => x.group.total), contains(10000));
    // ignore: avoid_print
    print('dashboard, 10,000 cuts: ${sw.elapsedMilliseconds}ms');
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });
}
