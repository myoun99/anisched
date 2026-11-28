import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/cut_numbers.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late CatalogueStore store;

  setUp(() {
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => DateTime(2026, 11, 27, 14));
  });
  tearDown(() => db.close());

  List<String> numbers(int ep) => store.cuts(ep).map((c) => c.number).toList();
  int stage(int w, String name) =>
      store.stages(w).firstWhere((s) => s.name == name).id;

  test('a work, an episode and its cuts in one call', () {
    final r = store.createWorkWithCuts(
      '극장판',
      '본편',
      'C001~C005, C007',
      partLabel: 'A',
    );
    expect(numbers(r.episodeId), [
      'C001',
      'C002',
      'C003',
      'C004',
      'C005',
      'C007',
    ]);
    expect(store.parts(r.episodeId).single.plannedCutCount, 6);
    expect(store.works().single.title, '극장판');
  });

  test('unreadable input creates nothing', () {
    expect(
      () => store.createWorkWithCuts('W', '#1', 'C1~C3, C9~C2'),
      throwsA(isA<CutNumbersException>()),
    );
    expect(store.works(), isEmpty);
  });

  test('missing numbers out, A/B/C splits in, shared cuts, renumbering', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C010~C016', partLabel: 'B');
    final lo = stage(w, 'LO');
    store.addTasksForPart(r.partId!, lo);

    // 결번: C013 does not exist after all.
    expect(store.removeCuts(r.episodeId, ['C013', 'C099']), ['C099']);
    expect(numbers(r.episodeId), [
      'C010',
      'C011',
      'C012',
      'C014',
      'C015',
      'C016',
    ]);

    // C012 splits into A, B, C — new cuts get the same stages.
    final c012 = store.cuts(r.episodeId)[2].id;
    final split = store.splitCut(c012, ['A', 'B', 'C']);
    expect(split.first, c012);
    expect(numbers(r.episodeId), [
      'C010', 'C011', 'C012A', 'C012B', 'C012C', 'C014', 'C015', 'C016', //
    ]);
    final g = store.partGroups().single;
    expect(g.tasks.map((t) => t.unitLabel), contains('C012C'));
    expect(g.total, 8);

    // C014–C016 are one shared cut: linked, each keeping its own row.
    final ids = {for (final c in store.cuts(r.episodeId)) c.number: c.id};
    final head = store.linkSharedCuts([
      ids['C016']!,
      ids['C014']!,
      ids['C015']!,
    ]);
    expect(head, ids['C014']);
    expect(numbers(r.episodeId).last, 'C016');
    final rows = store.partGroups().single.tasks;
    expect(rows, hasLength(8));
    expect({
      for (final t in rows) t.unitLabel: t.sharedLabel,
    }, containsPair('C015', 'C014-016'));
    expect(rows.firstWhere((t) => t.unitLabel == 'C010').sharedLabel, isNull);

    // Swap two numbers in one go.
    store.renumberCuts({ids['C010']!: 'C011', ids['C011']!: 'C010'});
    expect(numbers(r.episodeId).take(2), ['C010', 'C011']);
    expect(
      store.cuts(r.episodeId).first.id,
      ids['C011'],
    ); // the old C011 is now C010
    // A clash changes nothing.
    expect(() => store.renumberCuts({ids['C010']!: 'C012A'}), throwsStateError);
    expect(numbers(r.episodeId).first, 'C010');
  });

  test('shared cut numbers', () {
    expect(sharedCutNumber('C012', 'C014'), 'C012-014');
    expect(sharedCutNumber('C012', 'X3'), 'C012-X3');
  });

  test('clients, works and episodes can be edited', () {
    final c = store.addClient('A사');
    store
      ..renameClient(c, 'A스튜디오')
      ..setClientClosingDay(c, 25);
    expect(store.clients().single, (id: c, name: 'A스튜디오', closingDay: 25));
    final w = store.createWork('가제');
    store
      ..renameWork(w, '본제')
      ..setWorkClient(w, c)
      ..setWorkCurrency(w, 'KRW');
    expect(store.works().single, (
      id: w,
      title: '본제',
      currency: 'KRW',
      clientId: c,
    ));
    final ep = store.addEpisode(w, '#1');
    store.renameEpisode(ep, '#01', title: '시작');
    expect(store.episodes(w).single, (id: ep, number: '#01', title: '시작'));
  });

  test('1500 cuts: create, assign a stage, list', () {
    final w = store.createWork('W');
    final sw = Stopwatch()..start();
    final r = store.addEpisodeWithCuts(
      w,
      '극장판',
      'C0001~C1500',
      partLabel: 'All',
    );
    final tCreate = sw.elapsedMilliseconds;
    store.addTasksForPart(r.partId!, stage(w, '원화'));
    final tTasks = sw.elapsedMilliseconds - tCreate;
    final groups = store.partGroups();
    final tRead = sw.elapsedMilliseconds - tCreate - tTasks;
    expect(groups.single.total, 1500);
    // ignore: avoid_print
    print('1500 cuts: create ${tCreate}ms, tasks ${tTasks}ms, read ${tRead}ms');
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });

  test('shared cuts keep their own lengths and pay', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C3', partLabel: 'A');
    final genga = stage(w, '원화');
    store
      ..setEpisodeRate(r.episodeId, genga, const Rate(RateUnit.perSecond, 1000))
      ..setCutLength(r.cutIds[0], 2000)
      ..setCutLength(r.cutIds[1], 3000)
      ..setCutLength(r.cutIds[2], 4000)
      ..addTasksForPart(r.partId!, genga)
      ..linkSharedCuts([r.cutIds[1], r.cutIds[2]]);
    final g = store.partGroups().single;
    expect(g.pay, 2000 + 3000 + 4000);
    expect(g.tasks.map((t) => t.sharedLabel), [null, 'C2-3', 'C2-3']);
  });

  test('leaving a shared group; the group re-forms or dissolves', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C4', partLabel: 'A');
    store.addTasksForPart(r.partId!, stage(w, 'LO'));
    final ids = r.cutIds;
    Map<String, String?> labels() => {
      for (final t in store.partGroups().single.tasks)
        t.unitLabel: t.sharedLabel,
    };
    store.linkSharedCuts([ids[0], ids[1], ids[2]]);
    expect(labels()['C2'], 'C1-3');
    // The first cut leaves: C2 leads C2–C3.
    store.unlinkSharedCut(ids[0]);
    expect(labels(), {'C1': null, 'C2': 'C2-3', 'C3': 'C2-3', 'C4': null});
    // Re-linking a member moves it into the new group.
    store.linkSharedCuts([ids[2], ids[3]]);
    expect(labels(), {'C1': null, 'C2': null, 'C3': 'C3-4', 'C4': 'C3-4'});
    store.unlinkSharedCut(ids[3]);
    expect(labels().values.toSet(), {null});
    expect(() => store.linkSharedCuts([ids[0]]), throwsArgumentError);
  });

  test('start + count input, grid removal', () {
    expect(cutNumberRun(start: 98, count: 3), ['C098', 'C099', 'C100']);
    expect(cutNumberRun(start: 1, count: 2, prefix: '', width: 1), ['1', '2']);
    expect(() => cutNumberRun(start: 1, count: -1), throwsRangeError);
    final w = store.createWork('W');
    final ep = store.addEpisode(w, '#1');
    final added = store.addCuts(ep, cutNumberRun(start: 100, count: 5)).added;
    store.removeCutIds([added[1], added[3]]);
    expect(numbers(ep), ['C100', 'C102', 'C104']);
  });

  test('roles: picking one creates its stages\' tasks', () {
    expect(store.roles().map((r) => r.name), [
      '원화',
      '연출',
      '작감',
      '총작감',
      '콘티',
      '동화',
      '시아게',
      '캐릭터디자인',
    ]);
    expect(store.roles()[1].stages, ['LO 연출 수정', '원화 연출 수정']);
    expect(store.roles().first.stages, ['LO', '원화']);
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C3', partLabel: 'B');
    final genga = store.roles().first.id;
    final made = store.applyRole(genga, workId: w, partId: r.partId);
    expect(made, hasLength(6)); // 3 cuts × LO, 원화
    expect(store.partGroups().map((g) => g.stageName).toSet(), {'LO', '원화'});
    // Applying again adds nothing.
    expect(store.applyRole(genga, workId: w, partId: r.partId), isEmpty);
    // A role with a stage the work lacks adds that stage to the work.
    final niwon = store.createRole('2원', ['2원']);
    final solo = store.addCut(r.episodeId, 'C9');
    expect(store.applyRole(niwon, workId: w, cutIds: [solo]), hasLength(1));
    expect(store.stages(w).last.name, '2원');
    // Edit and remove roles.
    store
      ..renameRole(niwon, '제2원화')
      ..setRoleStages(niwon, ['2원', '2원', '동화']);
    final edited = store.roles().last;
    expect((edited.id, edited.name), (niwon, '제2원화'));
    expect(edited.stages, ['2원', '동화']);
    store.deleteRole(niwon);
    expect(store.roles(), hasLength(8));
  });

  test('checkboxes: tasks from a list of stages; a role ticks its boxes', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C2', partLabel: 'B');
    final lo = stage(w, 'LO');
    // "LO only" is not a role: just tick LO.
    expect(store.addTasksForStages([lo], partId: r.partId), hasLength(2));
    final sakkan = store.roles().firstWhere((x) => x.name == '작감').id;
    final ids = store.roleStageIds(sakkan, w);
    expect(
      ids.map((id) => store.stages(w).firstWhere((s) => s.id == id).name),
      ['LO 작감 수정', '원화 작감 수정'],
    );
    expect(
      store.addTasksForStages([lo, ...ids], partId: r.partId),
      hasLength(4), // LO already there
    );
  });

  test('cut numbers follow the format of their work', () {
    final w = store.createWork('W');
    expect(store.workCutFormat(w), (prefix: 'C', digits: 3));
    expect(store.cutNumberFor(w, 1), 'C001');
    final ep = store.addEpisode(w, '#1');
    store.addCutRun(ep, start: 98, count: 3);
    expect(numbers(ep), ['C098', 'C099', 'C100']);

    store.setWorkCutFormat(w, prefix: '', digits: 4);
    expect(store.cutNumberFor(w, 12), '0012');
    store.addCutRun(ep, start: 1, count: 2);
    expect(numbers(ep).take(2), ['0001', '0002']);
    expect(
      () => store.setWorkCutFormat(w, prefix: 'C', digits: 0),
      throwsRangeError,
    );
  });

  test('a shared pair is two cuts everywhere: count, progress, pace, pay', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C2', partLabel: 'B');
    final lo = stage(w, 'LO');
    store
      ..settings.restWeekdays = {}
      ..setEpisodeRate(r.episodeId, lo, const Rate(RateUnit.fixed, 2500))
      ..addTasksForPart(r.partId!, lo)
      ..setPartDue(r.partId!, lo, DateTime(2026, 11, 28))
      ..linkSharedCuts(r.cutIds);

    // Registration does not shrink the count.
    expect(store.cuts(r.episodeId), hasLength(2));
    expect(store.parts(r.episodeId).single.cutCount, 2);
    var g = store.partGroups().single;
    expect(g.total, 2);
    expect(g.tasks.map((t) => t.sharedLabel), ['C1-2', 'C1-2']);
    // Per-cut rate twice.
    expect(g.pay, 5000);
    // Two cuts over today and tomorrow.
    expect(store.paceOf(g)!.remaining, 2);
    expect(store.paceOf(g)!.perDay, 1);

    // Progress counts each: one handed is 1/2.
    store.setStatus(g.tasks.first.id, TaskStatus.submitted);
    g = store.partGroups().single;
    expect((g.handed, g.total), (1, 2));

    // Monthly totals pay both.
    store.setStatusMany(g.tasks.map((t) => t.id), TaskStatus.done);
    expect(store.monthlyTotals(2026, 11)['JPY']!.total, 5000);
  });

  test('the cut list shows shared groups and, on request, archived cuts', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C4');
    final ids = r.cutIds;
    store
      ..linkSharedCuts([ids[1], ids[2]])
      ..removeCutIds([ids[3]]);
    var rows = store.cuts(r.episodeId);
    expect(rows.map((c) => c.number), ['C1', 'C2', 'C3']);
    expect(rows.map((c) => c.sharedHeadCutId), [null, ids[1], ids[1]]);
    expect(rows.map((c) => c.sharedLabel), [null, 'C2-3', 'C2-3']);
    expect(rows.every((c) => !c.archived), isTrue);

    rows = store.cuts(r.episodeId, includeArchived: true);
    expect(rows.map((c) => (c.number, c.archived)), [
      ('C1', false),
      ('C2', false),
      ('C3', false),
      ('C4', true),
    ]);
    store.restore(ArchiveKind.cut, ids[3]);
    expect(store.cuts(r.episodeId).last.number, 'C4');
  });
}
