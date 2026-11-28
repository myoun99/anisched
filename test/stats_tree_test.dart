import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// The statistics drill-down (유저 2026-11-28): client → work → episode →
/// part → cut, folded from the same facts as the statistics tab.
void main() {
  final now = DateTime(2026, 11, 28, 14);
  final from = DateTime(2026, 11);
  final to = DateTime(2026, 12);
  late AppDatabase db;
  late CatalogueStore store;
  late int part;
  late List<int> tasks;

  void interval(DateTime start, Duration length, int task) => db.execute(
    'INSERT INTO work_intervals (started_at, stopped_at, task_id) '
    'VALUES (?, ?, ?);',
    [
      start.millisecondsSinceEpoch,
      start.add(length).millisecondsSinceEpoch,
      task,
    ],
  );

  StatsNode only(StatsNode n) => n.children.single;

  setUp(() {
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now);
    final client = store.addClient('회사');
    final work = store.createWork('작품', clientId: client);
    final lo = store.stages(work).firstWhere((s) => s.name == 'LO').id;
    final ep = store.addEpisode(work, '1');
    part = store.addPart(ep, 'A');
    final cuts = store.addCuts(ep, ['1', '2', '3'], partId: part).added;
    store
      ..setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 1000))
      ..linkSharedCuts([cuts[1], cuts[2]]);
    tasks = store.addTasksForPart(part, lo);
    store
      ..setPartDue(part, lo, DateTime(2026, 11, 30))
      ..setStatus(tasks[0], TaskStatus.submitted)
      ..setStatus(tasks[1], TaskStatus.done); // the pair, both done
  });

  tearDown(() => db.close());

  test('the root has the statistics total; the levels go down to the cut', () {
    interval(DateTime(2026, 11, 10, 10), const Duration(hours: 2), tasks[0]);
    final stats = store.stats(from: from, to: to).total;
    final root = store.statsTree(from: from, to: to);
    expect(
      (root.cuts, root.finished, root.handed, root.done, root.worked),
      (stats.cuts, stats.finished, stats.handed, stats.done, stats.worked),
    );
    expect(root.earned, stats.earned);
    expect((root.withDue, root.onTime), (1, 1));

    final client = only(root);
    final work = only(client);
    final episode = only(work);
    final partNode = only(episode);
    expect([client, work, episode, partNode].map((n) => (n.kind, n.label)), [
      (StatsNodeKind.client, '회사'),
      (StatsNodeKind.work, '작품'),
      (StatsNodeKind.episode, '#01'),
      (StatsNodeKind.part, 'A'),
    ]);
    expect(partNode.id, part);
    expect(partNode.children.map((c) => c.label), ['C001', 'C002', 'C003']);
    final leaf = partNode.children.first;
    expect(leaf.kind, StatsNodeKind.cut);
    final lo = leaf.stages['LO']!;
    expect(
      (lo.worked, lo.intervals, lo.take, lo.pay, lo.status),
      (const Duration(hours: 2), 1, 1, 1000, TaskStatus.submitted),
    );
  });

  test('a shared pair is one cut above the leaves, two in pay; each leaf '
      'counts its own', () {
    final partNode = only(
      only(only(only(store.statsTree(from: from, to: to)))),
    );
    expect((partNode.cuts, partNode.finished), (2, 2));
    // Submitted counts as done too: C001, and the pair once.
    expect(partNode.done, 2);
    expect(partNode.earned['JPY'], 3000); // the pair paid twice
    expect(partNode.children.map((c) => (c.cuts, c.done, c.earned['JPY'])), [
      (1, 1, 1000),
      (1, 1, 1000),
      (1, 1, 1000),
    ]);
  });

  test('timer time outside the range is left out, or cut at its edge', () {
    interval(DateTime(2026, 10, 3, 9), const Duration(hours: 3), tasks[0]);
    interval(DateTime(2026, 10, 31, 23), const Duration(hours: 2), tasks[0]);
    interval(DateTime(2026, 11, 20, 9), const Duration(hours: 1), tasks[2]);
    final root = store.statsTree(from: from, to: to);
    expect(root.worked, const Duration(hours: 2)); // 1 h at the edge + 1 h
    final leaves = only(only(only(only(root)))).children;
    expect(leaves.map((c) => c.stages['LO']!.intervals), [1, 0, 1]);
    expect(leaves.first.worked, const Duration(hours: 1));
    expect(root.firstWorkAt, DateTime(2026, 11).toUtc());
  });

  test('pay per hour: none without time, earned over time with it', () {
    var root = store.statsTree(from: from, to: to);
    expect(root.earned['JPY'], 3000);
    expect(root.perHour, isEmpty);
    interval(DateTime(2026, 11, 20, 9), const Duration(hours: 4), tasks[1]);
    root = store.statsTree(from: from, to: to);
    expect(root.perHour['JPY'], 750);
  });
}
