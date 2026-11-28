import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late CatalogueStore store;
  late WorkTimerStore timer;
  var now = DateTime(2026, 11, 2, 10);

  setUp(() {
    now = DateTime(2026, 11, 2, 10);
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now.toUtc());
    timer = WorkTimerStore(db, clock: () => now.toUtc());
  });
  tearDown(() => db.close());

  test('handed off: out of lists and pace, time stays in statistics', () async {
    final w = store.createWork('W');
    final r = store.addEpisodeWithCuts(w, '#1', 'C001~C004', partLabel: 'A');
    int stage(String n) => store.stages(w).firstWhere((s) => s.name == n).id;
    final genga = stage('원화');
    final lo = stage('LO');
    store
      ..addTasksForPart(r.partId!, genga)
      ..addTasksForPart(r.partId!, lo)
      ..setPartDue(r.partId!, genga, DateTime(2026, 11, 13))
      ..setEpisodeRate(r.episodeId, genga, const Rate(RateUnit.fixed, 1000));
    final gengaTasks = [
      for (final t in store.taskRows())
        if (t.stageId == genga) t.id,
    ];

    timer.start(taskId: gengaTasks[0]);
    now = DateTime(2026, 11, 2, 12);
    timer.stop();
    store.setStatus(gengaTasks[1], TaskStatus.done);

    final ids = store.handOffPart(r.partId!, genga, note: 'moved to B');
    expect(ids, hasLength(4));

    // Lists: the 원화 unit is gone; LO of the same cuts stays.
    expect(store.partGroups().map((g) => g.stageName), ['LO']);
    expect(store.holding().inHand, 4);
    final back = store.partGroups(includeHandedOff: true, includeDone: true);
    expect(back.map((g) => g.stageName), containsAll(['LO', '원화']));
    final row = store
        .taskRows(includeHandedOff: true)
        .firstWhere((t) => t.id == gengaTasks[0]);
    expect(row.handedOff, isTrue);
    expect(row.handedOffNote, 'moved to B');
    expect(store.monthlyTotals(2026, 11), isEmpty);

    // Statistics: time kept, results not.
    now = DateTime(2026, 11, 9);
    final s = store.stats(
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 9),
    );
    expect(s.total.worked, const Duration(hours: 2));
    expect(s.stages.map((x) => x.label), contains('원화'));
    expect(s.total.done, 0);
    expect(s.total.earned, isEmpty);
    expect(s.handedOff, 4);
    expect(s.works.single.cuts, 4); // the LO tasks only

    // The reader passes the filter through.
    final reader = SyncCatalogueReader(store);
    expect((await reader.partGroups()).length, 1);
    expect((await reader.partGroups(includeHandedOff: true)).length, 2);

    store.undoHandOff(ids);
    expect(store.partGroups().length, 2);
  });

  test('statistics narrowed to a client or a work', () async {
    final a = store.addClient('A');
    final b = store.addClient('B');
    final wa = store.createWork('WA', clientId: a);
    final wb = store.createWork('WB', clientId: b);
    final ta = store.addTask(
      store.stages(wa).first.id,
      cutId: store.addEpisodeWithCuts(wa, '#1', 'C001').cutIds.single,
    );
    final tb = store.addTask(
      store.stages(wb).first.id,
      cutId: store.addEpisodeWithCuts(wb, '#1', 'C001').cutIds.single,
    );
    timer.start(taskId: ta);
    now = DateTime(2026, 11, 2, 11);
    timer.toggle(taskId: tb);
    now = DateTime(2026, 11, 2, 13);
    timer.stop();
    store
      ..setStatus(ta, TaskStatus.submitted)
      ..setStatus(tb, TaskStatus.submitted);
    timer.start(); // time on no task
    now = DateTime(2026, 11, 2, 14);
    timer.stop();
    now = DateTime(2026, 11, 9);
    final from = DateTime(2026, 11, 2);
    final to = DateTime(2026, 11, 9);

    expect(store.stats(from: from, to: to).total.worked.inHours, 4);
    final onlyA = store.stats(from: from, to: to, clientId: a);
    expect(onlyA.total.handed, 1);
    expect(onlyA.total.worked, const Duration(hours: 1));
    expect(onlyA.works.single.label, 'WA');
    final onlyB = await SyncCatalogueReader(store)
        .stats(from: from, to: to, workId: wb);
    expect(onlyB.total.worked, const Duration(hours: 2));
    expect(onlyB.previous!.total.handed, 0);
    expect(
      store.stats(from: from, to: to, clientId: a, workId: wb).total.handed,
      0,
    );
  });
}
