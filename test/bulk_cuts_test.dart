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

    // C014–C016 are one shared cut.
    final ids = {for (final c in store.cuts(r.episodeId)) c.number: c.id};
    final kept = store.mergeCuts([ids['C016']!, ids['C014']!, ids['C015']!]);
    expect(kept, ids['C014']);
    expect(numbers(r.episodeId).last, 'C014-016');
    expect(store.partGroups().single.total, 6);

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

  test('archiving a merged-away cut can be undone', () {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C1~C3');
    final ids = r.cutIds;
    store.mergeCuts([ids[1], ids[2]]);
    expect(numbers(r.episodeId), ['C1', 'C2-3']);
    store.restore(ArchiveKind.cut, ids[2]);
    expect(numbers(r.episodeId), ['C1', 'C2-3', 'C3']);
  });
}
