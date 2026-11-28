import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late CatalogueStore store;
  final t0 = DateTime.utc(2026, 11, 27, 9);

  setUp(() {
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => t0);
  });
  tearDown(() => db.close());

  int stageId(int workId, String name) =>
      store.stages(workId).firstWhere((s) => s.name == name).id;

  group('pure rules', () {
    test('natural sort key orders cut numbers', () {
      final labels = ['C10', 'C2', 'c10A', 'C010', 'C1'];
      labels.sort((a, b) => naturalSortKey(a).compareTo(naturalSortKey(b)));
      expect(labels, ['C1', 'C2', 'C10', 'C010', 'c10A']);
      expect(naturalSortKey('C010'), naturalSortKey('C10'));
    });

    test('fixed and per-second pay', () {
      expect(const Rate(RateUnit.fixed, 4000).payFor(), 4000);
      // 3 s × 10000/s.
      expect(
        const Rate(RateUnit.perSecond, 10000).payFor(lengthMs: 3000),
        30000,
      );
      expect(const Rate(RateUnit.perSecond, 10000).payFor(), isNull);
    });

    test('per-second rates round the length by the chosen mode', () {
      const r = Rate(RateUnit.perSecond, 10000);
      int? pay(int ms, SecondsRounding m) =>
          r.payFor(lengthMs: ms, rounding: m);
      // Default: nearest second, half up.
      expect(r.payFor(lengthMs: 3500), 40000);
      expect(r.payFor(lengthMs: 3499), 30000);
      expect(pay(3500, SecondsRounding.exact), 35000);
      expect(pay(3001, SecondsRounding.up), 40000);
      expect(pay(3999, SecondsRounding.down), 30000);
      expect(pay(3000, SecondsRounding.up), 30000);
    });

    test('day range starts at the configured minute', () {
      final midnight = dayRange(DateTime(2026, 11, 28, 1), 0);
      expect(midnight.start, DateTime(2026, 11, 28));
      expect(midnight.end, DateTime(2026, 11, 29));
      final fiveAm = dayRange(DateTime(2026, 11, 28, 1), 300);
      expect(fiveAm.start, DateTime(2026, 11, 27, 5));
      expect(fiveAm.end, DateTime(2026, 11, 28, 5));
    });

    test('billing period closes at month end by default', () {
      final p = billingPeriod(2026, 2, null);
      expect(p.start, DateTime(2026, 2));
      expect(p.end, DateTime(2026, 3));
    });

    test('billing period with a 20th close spans months and years', () {
      final p = billingPeriod(2026, 1, 20);
      expect(p.start, DateTime(2025, 12, 21));
      expect(p.end, DateTime(2026, 1, 21));
    });

    test('a 31st close in a short month closes on its last day', () {
      final p = billingPeriod(2026, 3, 31);
      expect(p.start, DateTime(2026, 3));
      expect(p.end, DateTime(2026, 4));
    });
  });

  group('CatalogueStore', () {
    test('a new work gets the default stages in order, in yen', () {
      final w = store.createWork('작품A');
      expect(store.stages(w).map((s) => s.name), defaultStageNames);
      expect(
        db
            .select('SELECT currency FROM works WHERE id = ?', [w])
            .first
            .columnAt(0),
        'JPY',
      );
    });

    test('a task is either a cut or a storyboard, never both or neither', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final cut = store.addCut(ep, 'C001');
      final sb = store.addStoryboard(ep, '콘티');
      final lo = stageId(w, 'LO');
      expect(
        () => store.addTask(lo, cutId: cut, storyboardId: sb),
        throwsA(isA<SqliteException>()),
      );
      expect(() => store.addTask(lo), throwsA(isA<SqliteException>()));
      expect(store.addTask(stageId(w, '콘티'), storyboardId: sb), isPositive);
    });

    test('the same stage of the same cut is one live task', () {
      final w = store.createWork('작품A');
      final cut = store.addCut(store.addEpisode(w, '#01'), 'C001');
      final lo = stageId(w, 'LO');
      store.addTask(lo, cutId: cut);
      expect(
        () => store.addTask(lo, cutId: cut),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rates: episode default per stage, task override wins', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final lo = stageId(w, 'LO');
      final genga = stageId(w, '원화');
      store
        ..setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 3000))
        ..setEpisodeRate(ep, genga, const Rate(RateUnit.perSecond, 10000));
      final cut = store.addCut(ep, 'C001', lengthMs: 3000);
      final loTask = store.addTask(lo, cutId: cut);
      final gengaTask = store.addTask(genga, cutId: cut);
      expect(store.payFor(loTask), 3000);
      expect(store.payFor(gengaTask), 30000);

      final other = store.addCut(ep, 'C002');
      final overridden = store.addTask(
        lo,
        cutId: other,
        rate: const Rate(RateUnit.fixed, 5000),
      );
      expect(store.payFor(overridden), 5000);
      // Per-second rate on a cut with no length yet.
      expect(store.payFor(store.addTask(genga, cutId: other)), isNull);
    });

    test('retakes number 2, 3, … and are free unless paid', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final lo = stageId(w, 'LO');
      store.setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 3000));
      final task = store.addTask(lo, cutId: store.addCut(ep, 'C001'));

      store.setStatus(task, TaskStatus.submitted);
      expect(store.requestRetake(task), 2);
      expect(store.requestRetake(task), 3);
      expect(store.requestRetake(task, paidAmount: 1000), 4);
      expect(store.payFor(task), 4000);
      expect(
        db
            .select('SELECT status FROM tasks WHERE id = ?', [task])
            .first
            .columnAt(0),
        TaskStatus.retake.dbName,
      );

      store.setStatus(task, TaskStatus.done);
      final row = db.select(
        'SELECT status, submitted_at, done_at FROM tasks WHERE id = ?',
        [task],
      ).first;
      expect(TaskStatus.fromDb(row['status'] as String), TaskStatus.done);
      expect(row['done_at'], t0.millisecondsSinceEpoch);
      expect(row['submitted_at'], t0.millisecondsSinceEpoch);
    });

    test('several tasks change status in one go', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final lo = stageId(w, 'LO');
      final ids = [
        for (final c in ['C1', 'C2', 'C3'])
          store.addTask(lo, cutId: store.addCut(ep, c)),
      ];
      store.setStatusMany(ids.take(2), TaskStatus.submitted);
      final rows = db.select(
        'SELECT status, submitted_at FROM tasks ORDER BY id',
      );
      expect(rows.map((r) => r['status']), [
        'submitted',
        'submitted',
        'received',
      ]);
      expect(rows.first['submitted_at'], t0.millisecondsSinceEpoch);
    });

    test('a failed bulk change leaves every task as it was', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final lo = stageId(w, 'LO');
      final id = store.addTask(lo, cutId: store.addCut(ep, 'C1'));
      db.execute('''
CREATE TRIGGER no_done BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'done' AND NEW.id <> $id
BEGIN SELECT RAISE(ABORT, 'nope'); END;''');
      final other = store.addTask(lo, cutId: store.addCut(ep, 'C2'));
      expect(
        () => store.setStatusMany([id, other], TaskStatus.done),
        throwsA(isA<SqliteException>()),
      );
      expect(
        db.select('SELECT status FROM tasks WHERE id = ?', [
          id,
        ]).first['status'],
        'received',
      );
    });

    test('many cuts at once; existing numbers are skipped', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final part = store.addPart(ep, 'B', plannedCutCount: 4);
      store.addCut(ep, 'C101');
      final r = store.addCuts(
        ep,
        ['C100', 'C101', 'C102'],
        partId: part,
        lengthMs: 3000,
      );
      expect(r.added, hasLength(2));
      expect(r.skipped, ['C101']);
      expect(store.cuts(ep).map((c) => (c.number, c.partId)), [
        ('C100', part),
        ('C101', null),
        ('C102', part),
      ]);
      expect(store.parts(ep).single.cutCount, 2);
    });

    test('cuts move into a part of their episode only', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final other = store.addEpisode(w, '#02');
      final part = store.addPart(ep, 'B');
      final elsewhere = store.addPart(other, 'X');
      final c = store.addCut(ep, 'C1');
      store.setCutsPart([c], part);
      expect(store.cuts(ep).single.partId, part);
      expect(() => store.setCutsPart([c], elsewhere), throwsArgumentError);
      expect(store.cuts(ep).single.partId, part); // rolled back
      store.setCutsPart([c], null);
      expect(store.cuts(ep).single.partId, isNull);
    });

    test('parts, cut lengths and part deadlines can be edited', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final part = store.addPart(ep, 'B', plannedCutCount: 11);
      store
        ..renamePart(part, 'B파트')
        ..setPlannedCutCount(part, null);
      expect(store.parts(ep).single.label, 'B파트');
      expect(store.parts(ep).single.plannedCutCount, isNull);
      final c = store.addCut(ep, 'C1', partId: part);
      store.setCutLength(c, 2500);
      expect(store.cuts(ep).single.lengthMs, 2500);
      final lo = stageId(w, 'LO');
      final task = store.addTasksForPart(part, lo).single;
      store.setPartDue(part, lo, DateTime.utc(2026, 12, 10));
      expect(store.dueFor(task).fromPart, isTrue);
      store.clearPartDue(part, lo);
      expect(store.dueFor(task).dueAt, isNull);
    });

    test('pickers: clients, works, episodes', () {
      final client = store.addClient('스튜디오 X', closingDay: 20);
      store.createWork('작품A', clientId: client);
      final b = store.createWork('작품B');
      store
        ..addEpisode(b, '#10')
        ..addEpisode(b, '#2');
      expect(store.clients().single.closingDay, 20);
      expect(store.works().map((w) => w.title).toSet(), {'작품A', '작품B'});
      expect(store.episodes(b).map((e) => e.number), ['#02', '#10']);
    });

    test('archiving hides everything beneath; restoring brings it back', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final lo = stageId(w, 'LO');
      store.setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 1000));
      final part = store.addPart(ep, 'B');
      final c1 = store.addCut(ep, 'C1', partId: part);
      store.addCut(ep, 'C2', partId: part);
      final ids = store.addTasksForPart(part, lo);
      int visible() => store.partGroups().fold(0, (a, g) => a + g.total);
      expect(visible(), 2);

      for (final (kind, id) in [
        (ArchiveKind.work, w),
        (ArchiveKind.episode, ep),
        (ArchiveKind.part, part),
      ]) {
        store.archive(kind, id);
        expect(visible(), 0, reason: '$kind hides its tasks');
        store.restore(kind, id);
        expect(visible(), 2, reason: '$kind restores them');
      }
      store.archive(ArchiveKind.cut, c1);
      expect(visible(), 1);
      expect(store.cuts(ep).map((c) => c.number), ['C002']);
      store.archive(ArchiveKind.task, ids[1]);
      expect(visible(), 0);
      store
        ..restore(ArchiveKind.cut, c1)
        ..restore(ArchiveKind.task, ids[1]);
      expect(visible(), 2);

      // Archived work stops counting in monthly totals too.
      store.setStatusMany(ids, TaskStatus.done);
      expect(store.monthlyTotals(2026, 11)['JPY']!.total, 2000);
      store.archive(ArchiveKind.work, w);
      expect(store.monthlyTotals(2026, 11), isEmpty);
    });

    test('the trash lists what is archived, newest first', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final c = store.addCut(ep, 'C7');
      final t = store.addTask(stageId(w, 'LO'), cutId: c);
      store
        ..archive(ArchiveKind.task, t)
        ..archive(ArchiveKind.cut, c);
      final trash = store.archived();
      expect(trash.map((a) => (a.kind, a.label)).toSet(), {
        (ArchiveKind.task, 'C007 · LO'),
        (ArchiveKind.cut, '#01 C007'),
      });
    });

    test('a client\'s colour reaches its work\'s rows', () {
      final studio = store.addClient('스튜디오 X', color: 0xFF336699);
      final w = store.createWork('작품A', clientId: studio);
      final ep = store.addEpisode(w, '#1');
      final c1 = store.addCut(ep, 'C1');
      final c2 = store.addCut(ep, 'C2');
      final lo = stageId(w, 'LO');
      store
        ..addTask(lo, cutId: c1)
        ..setStatus(store.addTask(lo, cutId: c2), TaskStatus.done);
      final g = store.partGroups().single;
      expect((g.clientName, g.clientColor), ('스튜디오 X', 0xFF336699));
      expect(g.toSubmit, 2); // done is not handed in yet
      store.setStatus(g.tasks.last.id, TaskStatus.submitted);
      expect(store.partGroups().single.toSubmit, 1);
      store.setClientColor(studio, null);
      expect(store.clients().single.color, isNull);
      expect(store.partGroups().single.clientColor, isNull);
      final loose = store.createWork('회사 없음');
      store.addTask(
        stageId(loose, 'LO'),
        cutId: store.addCut(store.addEpisode(loose, '#1'), 'C1'),
      );
      expect(
        store.partGroups().where((g) => g.workId == loose).single.clientName,
        isNull,
      );
    });

    test('events: by day and time, grouped by episode, within the range', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#1');
      final gone = store.addEpisode(w, '#2');
      final day = DateTime(2026, 12, 3);
      final late = store.addEvent(
        episodeId: ep,
        date: day,
        timeMinutes: 14 * 60,
        title: '아후레코',
      );
      final allDay = store.addEvent(episodeId: ep, date: day, title: '납품');
      final mine = store.addEvent(date: day, title: '회의', note: '줌');
      store
        ..addEvent(episodeId: ep, date: DateTime(2026, 12, 10), title: '밖')
        ..addEvent(episodeId: gone, date: day, title: '보관된 화')
        ..archive(ArchiveKind.episode, gone);
      final range = (from: DateTime(2026, 12), to: DateTime(2026, 12, 10));
      var got = store.events(from: range.from, to: range.to);
      expect(got.keys.toSet(), {ep, null});
      expect(got[ep]!.map((e) => e.id), [allDay, late]);
      expect(got[ep]!.first.date, day);
      expect(got[null]!.single.note, '줌');
      store.updateEvent(
        mine,
        episodeId: ep,
        date: DateTime(2026, 12, 2),
        timeMinutes: 9 * 60,
        title: '회의',
      );
      store.deleteEvent(late);
      got = store.events(from: range.from, to: range.to);
      expect(got.keys, [ep]);
      expect(got[ep]!.map((e) => (e.id, e.timeMinutes)), [
        (mine, 9 * 60),
        (allDay, null),
      ]);
      expect(
        () => store.addEvent(date: day, timeMinutes: 24 * 60, title: 'x'),
        throwsRangeError,
      );
    });

    test('rows carry their stage\'s place in the work\'s list', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#1');
      final c = store.addCut(ep, 'C1');
      final lo = stageId(w, 'LO');
      final key = stageId(w, '원화');
      store
        ..addTask(lo, cutId: c)
        ..addTask(key, cutId: c);
      Map<String, int> places() => {
        for (final g in store.partGroups()) g.stageName: g.stagePosition,
      };
      expect(places()['LO']! < places()['원화']!, isTrue);
      final order = [for (final s in store.stages(w)) s.id]
        ..remove(key)
        ..insert(0, key);
      store.reorderStages(w, order);
      expect(places()['원화']! < places()['LO']!, isTrue);
    });

    test('numbers are stored as values and shown in the current style', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#7');
      final c = store.addCut(ep, 'C012A');
      store
        ..addCut(ep, 'BANK1')
        ..addTask(stageId(w, 'LO'), cutId: c);
      // The same value typed another way is the same cut.
      expect(store.addCuts(ep, ['12a', 'c012A', '012A']).skipped, hasLength(3));
      expect(store.cuts(ep).map((c) => c.number), ['C012A', 'BANK1']);
      store.settings
        ..cutStyle = (prefix: '', digits: 4)
        ..episodeStyle = (prefix: 'EP', digits: 3);
      // Every view follows the new style at once; typed names stay.
      expect(store.cuts(ep).map((c) => c.number), ['0012A', 'BANK1']);
      expect(store.episodes(w).single.number, 'EP007');
      final row = store.taskRows().single;
      expect((row.episodeNumber, row.cutNumber), ('EP007', '0012A'));
      expect(store.searchEpisodes(w, 'ep00').single.id, ep);
      store.renumberCuts({c: '13'});
      expect(store.cuts(ep).first.number, '0013');
    });

    test('restoring onto a reused cut number is refused', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final old = store.addCut(ep, 'C1');
      store.archive(ArchiveKind.cut, old);
      store.addCut(ep, 'C1');
      expect(() => store.restore(ArchiveKind.cut, old), throwsStateError);
    });

    test('a work edits its own stage list; presets stay as they were', () {
      final w = store.createWork('작품A');
      List<String> names() => store.stages(w).map((s) => s.name).toList();
      final lo = stageId(w, 'LO');
      final extra = store.addStage(w, 'LO 감독 수정', beforeStageId: lo);
      expect(names().indexOf('LO 감독 수정'), names().indexOf('LO') - 1);
      store.renameStage(extra, 'LO 감독 체크');
      expect(names(), contains('LO 감독 체크'));
      final end = store.addStage(w, '동화 체크');
      expect(names().last, '동화 체크');

      final reversed = [for (final s in store.stages(w)) s.id].reversed
          .toList();
      store.reorderStages(w, reversed);
      expect(names().first, '동화 체크');
      expect(
        () => store.reorderStages(w, reversed.skip(1).toList()),
        throwsArgumentError,
      );

      // Hiding a stage takes it out of the picker; its tasks stay.
      final ep = store.addEpisode(w, '#01');
      store.addTask(end, cutId: store.addCut(ep, 'C1'));
      store.archive(ArchiveKind.stage, end);
      expect(names(), isNot(contains('동화 체크')));
      expect(store.partGroups().single.stageName, '동화 체크');
      store.restore(ArchiveKind.stage, end);
      expect(names(), contains('동화 체크'));
      expect(store.presetStages(store.defaultPresetId()), defaultStageNames);
    });

    test('search: part of a name, recently used first, literal % and _', () {
      var t = DateTime(2026, 11, 1);
      final s2 = CatalogueStore(db, clock: () => t);
      final a = s2.addClient('Studio Alpha');
      final b = s2.addClient('스튜디오 베타');
      final old = s2.createWork('별빛 정류장', clientId: a);
      t = DateTime(2026, 11, 2);
      final fresh = s2.createWork('별의 노래', clientId: b);
      s2.createWork('100%_test', clientId: b);
      expect(s2.searchWorks('별').map((w) => w.id), [fresh, old]);
      // Activity on the older work brings it to the top.
      t = DateTime(2026, 11, 5);
      final ep = s2.addEpisode(old, '#1');
      s2.addTask(stageId(old, 'LO'), cutId: s2.addCut(ep, 'C1'));
      expect(s2.searchWorks('별').map((w) => w.id), [old, fresh]);
      expect(s2.searchWorks('별', clientId: b).map((w) => w.id), [fresh]);
      expect(s2.searchWorks('%_').map((w) => w.title), ['100%_test']);
      expect(s2.searchWorks('0_t'), isEmpty);
      expect(s2.searchClients('alpha').single.id, a);
      expect(s2.searchClients('').map((c) => c.id), [a, b]);
      s2
        ..addEpisode(fresh, '#02')
        ..addEpisode(fresh, '#12')
        ..renameEpisode(s2.addEpisode(fresh, '#03'), '#03', title: '바다');
      expect(s2.searchEpisodes(fresh, '2').map((e) => e.number), [
        '#02',
        '#12',
      ]);
      expect(s2.searchEpisodes(fresh, '바다').single.number, '#03');
    });

    test('a failed createWork leaves no half-made work', () {
      db.execute('DROP TABLE work_stages;');
      expect(() => store.createWork('작품A'), throwsA(isA<SqliteException>()));
      expect(db.select('SELECT * FROM works'), isEmpty);
    });

    test('seconds rounding is a setting, nearest by default', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final genga = stageId(w, '원화');
      store.setEpisodeRate(ep, genga, const Rate(RateUnit.perSecond, 10000));
      final task = store.addTask(
        genga,
        cutId: store.addCut(ep, 'C001', lengthMs: 3500),
      );
      expect(store.payFor(task), 40000);
      store.settings.secondsRounding = SecondsRounding.down;
      expect(store.payFor(task), 30000);
      expect(CatalogueStore(db).settings.secondsRounding, SecondsRounding.down);
    });

    test('a work remembers its default rate unit, per cut by default', () {
      final w = store.createWork('작품A');
      expect(store.workDefaultRateUnit(w), RateUnit.fixed);
      store.setWorkDefaultRateUnit(w, RateUnit.perSecond);
      expect(store.workDefaultRateUnit(w), RateUnit.perSecond);
    });

    test('a work can override the app rounding', () {
      final w = store.createWork('작품A');
      final other = store.createWork('작품B');
      int perSecondTask(int work) {
        final ep = store.addEpisode(work, '#01');
        final genga = stageId(work, '원화');
        store.setEpisodeRate(ep, genga, const Rate(RateUnit.perSecond, 10000));
        return store.addTask(
          genga,
          cutId: store.addCut(ep, 'C001', lengthMs: 3500),
        );
      }

      final a = perSecondTask(w);
      final b = perSecondTask(other);
      store.setWorkRounding(w, SecondsRounding.exact);
      expect(store.payFor(a), 35000);
      expect(store.payFor(b), 40000); // app default: nearest
      store.settings.secondsRounding = SecondsRounding.down;
      expect(store.payFor(a), 35000); // the work's own wins
      expect(store.payFor(b), 30000);
      final byTask = {for (final r in store.taskRows()) r.id: r.pay};
      expect(byTask, {a: 35000, b: 30000});
      store.setWorkRounding(w, null);
      expect(store.payFor(a), 30000);
    });

    test('a cut can carry its own rate inside a part', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final lo = stageId(w, 'LO');
      store.setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 2500));
      final part = store.addPart(ep, 'B');
      store
        ..addCut(ep, 'C1', partId: part)
        ..addCut(ep, 'C2', partId: part);
      final ids = store.addTasksForPart(part, lo);
      store.setTaskRate(ids[1], const Rate(RateUnit.fixed, 4000));
      expect(store.payFor(ids[0]), 2500);
      expect(store.payFor(ids[1]), 4000);
      expect(store.partGroups().single.pay, 6500);
      store.setTaskRate(ids[1], null);
      expect(store.payFor(ids[1]), 2500);
    });

    test('day start is a setting, midnight by default', () {
      expect(store.settings.dayStartMinutes, 0);
      store.settings.dayStartMinutes = 300;
      expect(store.settings.dayStartMinutes, 300);
      expect(() => store.settings.dayStartMinutes = 24 * 60, throwsRangeError);
    });
  });

  group('stage presets', () {
    test('the default preset starts as the factory list', () {
      expect(store.presetStages(store.defaultPresetId()), defaultStageNames);
    });

    test('new works copy the edited preset; old works keep theirs', () {
      final before = store.createWork('작품A');
      final preset = store.defaultPresetId();
      store.setPresetStages(preset, ['LO', 'LO/작감', '원화']);
      final after = store.createWork('작품B');
      expect(store.stages(after).map((s) => s.name), ['LO', 'LO/작감', '원화']);
      expect(store.stages(before).map((s) => s.name), defaultStageNames);
    });

    test('several presets; a work is made from the chosen one', () {
      final sakkan = store.createPreset('작감용', ['LO/작감', '원화/작감']);
      expect(store.presets().map((p) => p.name), ['기본', '작감용']);
      expect(store.presets().first.isDefault, isTrue);
      final w = store.createWork('작품B', presetId: sakkan);
      expect(store.stages(w).map((s) => s.name), ['LO/작감', '원화/작감']);
      expect(
        store.stages(store.createWork('작품C')).map((s) => s.name),
        defaultStageNames,
      );
    });

    test('the default can move; it cannot be deleted', () {
      final basic = store.defaultPresetId();
      final other = store.createPreset('A사', ['LO', '원화']);
      expect(() => store.deletePreset(basic), throwsStateError);
      store.setDefaultPreset(other);
      expect(store.defaultPresetId(), other);
      expect(store.presets().where((p) => p.isDefault), hasLength(1));
      final w = store.createWork('작품D');
      store
        ..deletePreset(basic)
        ..renamePreset(other, 'A사 기본');
      expect(store.presets().map((p) => p.name), ['A사 기본']);
      expect(store.stages(w).map((s) => s.name), ['LO', '원화']);
    });

    test('moving the default to a missing preset changes nothing', () {
      final basic = store.defaultPresetId();
      expect(() => store.setDefaultPreset(9999), throwsArgumentError);
      expect(store.defaultPresetId(), basic);
    });

    test('there is only one default preset', () {
      expect(
        () => db.execute(
          "INSERT INTO stage_presets (name, is_default) VALUES ('X', 1)",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('parts', () {
    test('cut tasks follow the part deadline unless they set their own', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final part = store.addPart(ep, 'B', plannedCutCount: 11);
      final lo = stageId(w, 'LO');
      final c100 = store.addCut(ep, 'C100', partId: part);
      final c101 = store.addCut(ep, 'C101', partId: part);
      final partDue = DateTime.utc(2026, 12, 10);
      store.setPartDue(part, lo, partDue);

      final ids = store.addTasksForPart(part, lo);
      expect(ids, hasLength(2));
      expect(store.dueFor(ids.first), (dueAt: partDue, fromPart: true));

      final own = DateTime.utc(2026, 12, 5);
      db.execute('UPDATE tasks SET due_at = ? WHERE cut_id = ?', [
        own.millisecondsSinceEpoch,
        c101,
      ]);
      final t101 =
          db
                  .select('SELECT id FROM tasks WHERE cut_id = ?', [c101])
                  .first
                  .columnAt(0)
              as int;
      expect(store.dueFor(t101), (dueAt: own, fromPart: false));

      // Moving the part deadline moves the cuts that follow it.
      final later = DateTime.utc(2026, 12, 12);
      store.setPartDue(part, lo, later);
      final t100 =
          db
                  .select('SELECT id FROM tasks WHERE cut_id = ?', [c100])
                  .first
                  .columnAt(0)
              as int;
      expect(store.dueFor(t100).dueAt, later);
      expect(store.dueFor(t101).dueAt, own);
    });

    test('addTasksForPart skips cuts that already have the stage', () {
      final w = store.createWork('작품A');
      final ep = store.addEpisode(w, '#01');
      final part = store.addPart(ep, 'B');
      final lo = stageId(w, 'LO');
      store.addCut(ep, 'C100', partId: part);
      expect(store.addTasksForPart(part, lo), hasLength(1));
      store.addCut(ep, 'C101', partId: part);
      expect(store.addTasksForPart(part, lo), hasLength(1));
      expect(store.addTasksForPart(part, lo), isEmpty);
    });

    test('a task outside any part has only its own deadline', () {
      final w = store.createWork('작품A');
      final cut = store.addCut(store.addEpisode(w, '#01'), 'C001');
      final task = store.addTask(stageId(w, 'LO'), cutId: cut);
      expect(store.dueFor(task), (dueAt: null, fromPart: false));
    });
  });

  group('monthly totals', () {
    test('count by completion date, per currency, per closing day', () {
      db.execute("INSERT INTO clients (name, closing_day) VALUES ('X', 20)");
      final client20 = db.lastInsertRowId;
      final yen = store.createWork('엔 작품', clientId: client20);
      final won = store.createWork('원 작품', currency: 'KRW');

      int doneTask(int work, String cutNo, int rate, DateTime doneAt) {
        final ep = store.addEpisode(work, '#$cutNo');
        final lo = stageId(work, 'LO');
        store.setEpisodeRate(ep, lo, Rate(RateUnit.fixed, rate));
        final t = store.addTask(lo, cutId: store.addCut(ep, cutNo));
        CatalogueStore(db, clock: () => doneAt).setStatus(t, TaskStatus.done);
        return t;
      }

      // Client closes on the 20th: Nov period = Oct 21 .. Nov 20.
      doneTask(yen, 'C1', 3000, DateTime(2026, 10, 25, 12));
      doneTask(yen, 'C2', 4000, DateTime(2026, 11, 20, 23));
      doneTask(yen, 'C3', 9999, DateTime(2026, 11, 21, 1)); // December
      // No client: calendar month.
      doneTask(won, 'C4', 50000, DateTime(2026, 11, 1));
      doneTask(won, 'C5', 99999, DateTime(2026, 10, 31, 23)); // October
      // Done but unpriced.
      final ep = store.addEpisode(won, '#x');
      final t = store.addTask(
        stageId(won, 'LO'),
        cutId: store.addCut(ep, 'C6'),
      );
      CatalogueStore(
        db,
        clock: () => DateTime(2026, 11, 2),
      ).setStatus(t, TaskStatus.done);

      final totals = store.monthlyTotals(2026, 11);
      expect(totals['JPY'], (total: 7000, unpriced: 0));
      expect(totals['KRW'], (total: 50000, unpriced: 1));
    });
  });
}
