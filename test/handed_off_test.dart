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
}
