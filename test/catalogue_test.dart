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
      expect(store.episodes(b).map((e) => e.number), ['#2', '#10']);
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
      store.setPresetStages(preset, ['LO', 'LO 작감 수정', '원화']);
      final after = store.createWork('작품B');
      expect(store.stages(after).map((s) => s.name), ['LO', 'LO 작감 수정', '원화']);
      expect(store.stages(before).map((s) => s.name), defaultStageNames);
    });

    test('several presets; a work is made from the chosen one', () {
      final sakkan = store.createPreset('작감용', ['LO 작감 수정', '원화 작감 수정']);
      expect(store.presets().map((p) => p.name), ['기본', '작감용']);
      expect(store.presets().first.isDefault, isTrue);
      final w = store.createWork('작품B', presetId: sakkan);
      expect(store.stages(w).map((s) => s.name), ['LO 작감 수정', '원화 작감 수정']);
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
