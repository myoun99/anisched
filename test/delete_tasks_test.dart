import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cards put away (보관, restorable) and deleted for good (완전 삭제), with
/// everything hanging off them.
void main() {
  final now = DateTime(2026, 11, 28, 14);
  late AppDatabase db;
  late CatalogueStore store;
  late int client;
  late int work;
  late int episode;
  late int part;
  late int lo;
  late int genga;
  late List<int> cuts;
  late List<int> loTasks;
  late List<int> gengaTasks;

  int count(String table) =>
      db.select('SELECT COUNT(*) AS n FROM $table;').first['n'] as int;

  /// Every row a card can carry, on the LO card of [part] and its first
  /// task.
  void decorateLoCard() {
    final t = loTasks.first;
    final at = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO work_intervals (started_at, stopped_at, task_id) '
      'VALUES (?, ?, ?);',
      [at, at + 25 * 60 * 1000, t],
    );
    store
      ..requestRetake(t)
      ..setTaskDue(t, now.add(const Duration(days: 2)))
      ..extendDue(DueTarget.task(t), now.add(const Duration(days: 3)))
      ..setPartDue(part, lo, now.add(const Duration(days: 4)))
      ..extendDue(DueTarget.part(part, lo), now.add(const Duration(days: 5)))
      ..setPartPlan(part, lo, start: now, end: now.add(const Duration(days: 3)))
      ..setPartWaiting(part, lo, waiting: true, reason: 'BG')
      ..pinLane('part:$part:$lo', 1)
      ..setGroupOrder(['part:$part:$lo'])
      ..setTimerTarget(t);
  }

  setUp(() {
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now);
    client = store.addClient('회사');
    work = store.createWork('작품', clientId: client);
    final stages = {for (final s in store.stages(work)) s.name: s.id};
    lo = stages['LO']!;
    genga = stages['원화']!;
    episode = store.addEpisode(work, '1');
    store
      ..setEpisodeRate(episode, lo, const Rate(RateUnit.fixed, 3000))
      ..addEvent(episodeId: episode, date: now, title: '아후레코');
    part = store.addPart(episode, 'A');
    cuts = store.addCuts(episode, ['1', '2'], partId: part).added;
    loTasks = store.addTasksForPart(part, lo);
    gengaTasks = <int>[];
  });

  tearDown(() => db.close());

  test('archived tasks leave every view and come back on restore', () {
    store.setTimerTarget(loTasks.first);
    store.archiveTasks(loTasks);
    expect(store.partGroups(), isEmpty);
    expect(store.timerTarget(), isNull);
    expect(store.stagePaces(), isEmpty);
    final shown = store.partGroups(includeArchived: true);
    expect(shown.single.archived, isTrue);
    expect(shown.single.tasks.map((t) => t.id), loTasks);

    store.restoreTasks(loTasks);
    final back = store.partGroups().single;
    expect(back.archived, isFalse);
    expect(back.tasks.map((t) => t.id), loTasks);
    expect(store.timerTarget(), loTasks.first);
  });

  test('deleting the last tasks takes the cuts, part, episode and work, '
      'and every row hanging off them; the client stays', () {
    decorateLoCard();
    expect(store.deletionSummary(loTasks), (
      tasks: 2,
      cuts: 2,
      episodes: 1,
      works: 1,
      timerMinutes: 25,
    ));

    store.deleteTasks(loTasks);
    for (final table in const [
      'tasks',
      'cuts',
      'parts',
      'episodes',
      'works',
      'work_stages',
      'work_intervals',
      'retakes',
      'due_revisions',
      'part_stage_dues',
      'part_stage_plans',
      'part_stage_waits',
      'episode_rates',
      'events',
      'lane_pins',
      'group_order',
    ]) {
      expect(count(table), 0, reason: table);
    }
    expect(store.timerTarget(), isNull);
    expect(count('clients'), 1);
    expect(client, isPositive);
  });

  test('a cut with another stage still on it stays, and so does that card', () {
    gengaTasks = store.addTasksForPart(part, genga);
    store
      ..setPartDue(part, genga, now.add(const Duration(days: 9)))
      ..archiveTasks([gengaTasks.last]); // archived ones still count
    decorateLoCard();
    expect(
      store.deletionSummary(loTasks),
      (tasks: 2, cuts: 0, episodes: 0, works: 0, timerMinutes: 25),
    );

    store.deleteTasks(loTasks);
    expect(db.select('SELECT id FROM cuts;').map((r) => r['id']), cuts);
    expect(
      db.select('SELECT stage_id FROM part_stage_dues;').single['stage_id'],
      genga,
    );
    expect(count('part_stage_plans'), 0);
    // The 원화 card is held in its lane (places hold before a change);
    // the LO card's pin and order are gone.
    expect(
      db.select('SELECT group_key FROM lane_pins;').map((r) => r['group_key']),
      ['part:$part:$genga'],
    );
    final left = store.partGroups(includeArchived: true).single;
    expect(left.key, 'part:$part:$genga');
    expect(left.tasks.map((t) => t.id), gengaTasks);
  });

  test('deleting part of a card keeps the card and its rows; no row points '
      'at what is gone', () {
    decorateLoCard();
    store.deleteTasks([loTasks.first]);
    expect(db.select('SELECT id FROM cuts;').single['id'], cuts.last);
    expect(count('part_stage_dues'), 1);
    expect(count('lane_pins'), 1);
    expect(count('work_intervals'), 0);
    expect(count('retakes'), 0);
    expect(
      db.select('SELECT task_id FROM due_revisions WHERE task_id IS NOT NULL'),
      isEmpty,
    );
    expect(store.timerTarget(), isNull);
    expect(db.select('PRAGMA foreign_key_check;'), isEmpty);
    expect(store.partGroups().single.tasks.single.id, loTasks.last);
  });
}
