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
      expect(
        const Rate(RateUnit.perSecond, 10000).payFor(lengthMs: 3500),
        35000,
      );
      expect(const Rate(RateUnit.perSecond, 10000).payFor(), isNull);
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

    test('a failed createWork leaves no half-made work', () {
      db.execute('DROP TABLE work_stages;');
      expect(() => store.createWork('작품A'), throwsA(isA<SqliteException>()));
      expect(db.select('SELECT * FROM works'), isEmpty);
    });
  });
}
