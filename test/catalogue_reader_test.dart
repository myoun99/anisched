import 'dart:io';

import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final now = DateTime(2026, 11, 27, 14);
  late Directory dir;
  late String path;
  late Database db;
  late CatalogueStore store;
  late int lo;
  late int ep;
  late int part;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('anisched-reader');
    path = '${dir.path}/app.db';
    db = openAppDatabase(path);
    store = CatalogueStore(db, clock: () => now);
    final w = store.createWork('별빛 정류장');
    ep = store.addEpisode(w, '#07');
    lo = store.stages(w).firstWhere((s) => s.name == 'LO').id;
    store.setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 3000));
    part = store.addPart(ep, 'B');
    for (final c in ['C1', 'C2', 'C3']) {
      store.addCut(ep, c, partId: part);
    }
    store
      ..setPartDue(part, lo, now.add(const Duration(days: 2)))
      ..addTasksForPart(part, lo);
  });

  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  Future<BackgroundCatalogueReader> openReader() async {
    final r = await BackgroundCatalogueReader.open(
      path,
      writer: db,
      clock: () => now,
    );
    addTearDown(r.close);
    return r;
  }

  String describe(List<PartStageRow> groups) => [
    for (final g in groups)
      '${g.key} ${g.partLabel} ${g.stageName} ${g.handed}/${g.total} '
          '${g.status.name} ${g.pay} ${g.dueAt}',
  ].join('\n');

  test('answers match the store on the main isolate', () async {
    final reader = await openReader();
    expect(describe(await reader.partGroups()), describe(store.partGroups()));
    final today = await reader.today();
    expect(today.entries.single.group.partLabel, 'B');
    expect(today.entries.single.pace!.remaining, 3);
    expect(today.cutsToday, store.today().cutsToday);
    expect(await reader.monthlyTotals(2026, 11), store.monthlyTotals(2026, 11));
    expect(
      (await reader.stagePaces()).map((u) => u.stageName),
      store.stagePaces().map((u) => u.stageName),
    );
    expect((await reader.signals()).keys, store.signals().keys);
    expect(await reader.works(), store.works());
    expect(await reader.episodes(1), store.episodes(1));
    expect(await reader.parts(ep), store.parts(ep));
    expect(await reader.cuts(ep), store.cuts(ep));
    expect(
      await reader.cuts(ep, includeArchived: true),
      store.cuts(ep, includeArchived: true),
    );
    expect(await reader.clients(), store.clients());
    expect(await reader.weekHours(), store.weekHours());
    expect(await reader.dayIntervals(), store.dayIntervals());
    final taskIds = [for (final t in store.taskRows(includeDone: true)) t.id];
    expect(await reader.workedOn(taskIds), store.workedOn(taskIds));
    expect((await reader.runningTimer())?.id, store.runningTimer()?.id);
    expect(
      (await reader.intervalsOf(taskIds.first)).map((i) => i.id),
      store.intervalsOf(taskIds.first).map((i) => i.id),
    );
    expect(
      (await reader.tasksBeside(taskIds.first)).map((t) => t.id),
      store.tasksBeside(taskIds.first).map((t) => t.id),
    );
    final from = DateTime(2026, 10, 1);
    final to = DateTime(2026, 12, 1);
    // Arguments reach the store: a filter that matches nothing, a bucket.
    final viaReader = await reader.stats(
      from: from,
      to: to,
      bucket: StatsBucket.month,
      workId: 999,
    );
    final direct = store.stats(
      from: from,
      to: to,
      bucket: StatsBucket.month,
      workId: 999,
    );
    expect(viaReader.periods.length, direct.periods.length);
    expect(viaReader.total.cuts, direct.total.cuts);
    expect(
      (await reader.stats(from: from, to: to)).total.cuts,
      store.stats(from: from, to: to).total.cuts,
    );
    expect(await reader.holding(), store.holding());
    store.addEvent(episodeId: ep, date: DateTime(2026, 11, 28), title: 'E');
    final window = (from: DateTime(2026, 11), to: DateTime(2026, 12));
    expect(
      await reader.events(from: window.from, to: window.to),
      store.events(from: window.from, to: window.to),
    );
    expect(await reader.lanes(), store.lanes());
    final due = DueTarget.part(part, lo);
    expect(
      (await reader.dueRevisions(due)).map((r) => r.dueAt),
      store.dueRevisions(due).map((r) => r.dueAt),
    );
    store.handOff([taskIds.first]);
    expect(
      (await reader.partGroups(includeHandedOff: true)).single.total,
      store.partGroups(includeHandedOff: true).single.total,
    );
    expect(
      (await reader.partGroups()).single.total,
      store.partGroups().single.total,
    );
    expect(await reader.archived(), store.archived());
    expect(await reader.hasGroupOrder(), store.hasGroupOrder);
    expect(await reader.numberStyles(), store.numberStyles());
    expect(await reader.searchWorks('별'), store.searchWorks('별'));
    expect(await reader.searchClients(''), store.searchClients(''));
    expect(await reader.searchEpisodes(1, '07'), store.searchEpisodes(1, '07'));
    expect(
      (await reader.roles()).map((r) => '${r.name}:${r.stages}'),
      store.roles().map((r) => '${r.name}:${r.stages}'),
    );
    expect(
      (await reader.calendarLayout()).layout.laneOf,
      store.calendarLayout().layout.laneOf,
    );
  });

  test('a read after a write sees the write', () async {
    final reader = await openReader();
    expect((await reader.partGroups()).single.handed, 0);
    final id = store.partGroups().single.tasks.first.id;
    store.setStatus(id, TaskStatus.submitted);
    expect((await reader.partGroups()).single.handed, 1);
  });

  test('a read overtaken by a write is asked again, never stale', () async {
    final reader = await openReader();
    final before = reader.generation;
    final pending = reader.partGroups(); // in flight…
    final id = store.partGroups().single.tasks.first.id;
    store.setStatus(id, TaskStatus.submitted); // …when this lands
    expect(reader.generation, greaterThan(before));
    expect((await pending).single.handed, 1);
  });

  test('submitted units are hidden unless asked for', () async {
    final reader = await openReader();
    store.setStatusMany(
      store.partGroups().single.tasks.map((t) => t.id),
      TaskStatus.submitted,
    );
    expect(await reader.partGroups(), isEmpty);
    expect(await reader.partGroups(includeDone: true), hasLength(1));
  });

  test('a failing query fails its future, and the reader goes on', () async {
    final reader = await openReader();
    db.execute('ALTER TABLE parts RENAME TO parts_gone');
    await expectLater(
      reader.partGroups(),
      throwsA(isA<CatalogueReadException>()),
    );
    db.execute('ALTER TABLE parts_gone RENAME TO parts');
    expect(await reader.partGroups(), hasLength(1));
  });

  test('closing fails later reads; closing twice is fine', () async {
    final reader = await openReader();
    await reader.close();
    await reader.close();
    await expectLater(reader.partGroups(), throwsStateError);
  });

  test('a dead isolate leaves no read hanging', () async {
    final reader = await openReader();
    final reads = [for (var i = 0; i < 20; i++) reader.partGroups()];
    reader.debugKill();
    final outcomes = await Future.wait([
      for (final r in reads)
        r.then(
          (_) => 'ok',
          onError: (Object e) => e is StateError ? 'gone' : '$e',
        ),
    ]).timeout(const Duration(seconds: 5));
    expect(outcomes.toSet().difference({'ok', 'gone'}), isEmpty);
    await expectLater(reader.partGroups(), throwsStateError);
  });

  test('opening a missing file fails instead of hanging', () async {
    await expectLater(
      BackgroundCatalogueReader.open(
        '${dir.path}/missing.db',
        writer: db,
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<CatalogueReadException>()),
    );
  });

  test('the sync reader is the same API for tests', () async {
    final reader = SyncCatalogueReader(store);
    expect(describe(await reader.partGroups()), describe(store.partGroups()));
    await reader.close();
    await expectLater(reader.today(), throwsStateError);
  });
}
