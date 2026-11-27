import 'package:anisched/src/controllers/registration.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  test('the cut draft counts missing, split and shared cuts', () {
    final c = CutDraft(count: 10)
      ..toggleRemoved(['C003'])
      ..toggleSplit(['C005'])
      ..toggleShared(['C008', 'C007']);
    expect(c.cells.length, 9);
    expect(c.label('C007'), 'C007-008');
    expect(c.total, 10 - 1 + 1);
    c.toggleRemoved(['C003']);
    expect(c.removed, isEmpty);
    expect(c.canShare(['C007']), isTrue);
  });

  test('register writes a part, cuts, tasks per stage, splits and pairs', () {
    final store = CatalogueStore(openAppDatabase(':memory:'), clock: () => now);
    final cuts = CutDraft(count: 6)
      ..toggleRemoved(['C002'])
      ..toggleSplit(['C004'])
      ..toggleShared(['C005', 'C006']);
    final due = DateTime(2026, 12, 20, 23, 59);
    final tasks = register(
      store,
      RegistrationDraft(
        newWorkTitle: '새벽의 정원',
        episodeNumber: '#01',
        partLabel: 'A',
        stages: ['LO', '원화'],
        cuts: cuts,
        dueAt: due,
      ),
    );
    final work = store.works().single;
    expect(work.title, '새벽의 정원');
    final ep = store.episodes(work.id).single;
    final numbers = store.cuts(ep.id).map((c) => c.number).toList();
    expect(numbers, containsAll(['C001', 'C003', 'C004A', 'C004B', 'C005']));
    expect(numbers, isNot(contains('C002')));
    final groups = store.partGroups();
    expect(groups.map((g) => g.stageName).toSet(), {'LO', '원화'});
    expect(groups.every((g) => g.total == 6), isTrue);
    expect(tasks.length, 10);
    expect(groups.every((g) => g.dueAt!.isAtSameMomentAs(due)), isTrue);
  });

  test('without a part every cut gets its own deadline', () {
    final store = CatalogueStore(openAppDatabase(':memory:'), clock: () => now);
    final w = store.createWork('별빛 정류장');
    final due = DateTime(2026, 12, 1, 23, 59);
    register(
      store,
      RegistrationDraft(
        workId: w,
        episodeNumber: '#08',
        stages: ['원화'],
        cuts: CutDraft(start: 150, count: 3),
        dueAt: due,
      ),
    );
    final g = store.partGroups().single;
    expect(g.total, 3);
    expect(g.dueAt!.isAtSameMomentAs(due), isTrue);
  });
}
