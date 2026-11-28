import 'package:anisched/src/controllers/registration.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 27, 14);

CatalogueStore fresh() =>
    CatalogueStore(openAppDatabase(':memory:'), clock: () => now);

void main() {
  test('a shared pair stays two cuts; splits and missing count', () {
    final c = CutDraft(count: 10)
      ..toggleRemoved(['C003'])
      ..toggleSplit(['C005'])
      ..toggleShared(['C008', 'C007']);
    expect(c.cells.length, 10);
    expect(c.label('C007'), 'C007-008');
    expect(c.partner('C008'), 'C007');
    expect(c.total, 10 - 1 + 1);
    expect(c.canShare(['C007']), isTrue);
    expect(c.canShare(['C007', 'C001']), isFalse);
    c.toggleShared(['C008']);
    expect(c.shared, isEmpty);
  });

  test('cuts added and renamed by hand; clashes are found', () {
    final c = CutDraft(count: 3)
      ..add('BANK1')
      ..add('C002')
      ..rename('C001', 'C12A');
    expect(c.cells, ['C001', 'C002', 'C003', 'BANK1']);
    expect(c.nameOf('C001'), 'C12A');
    expect(c.clashes(), isEmpty);
    c.rename('C003', 'BANK1');
    expect(c.clashes(), {'C003', 'BANK1'});
    expect(c.clashes({'C002'}), containsAll(['C002']));
  });

  test('C012 registered, then 12 is the same cut: refused (유저 2026-11-28 '
      'bug)', () {
    final store = fresh();
    final w = store.createWork('W');
    final ep = store.addEpisode(w, '#01');
    RegistrationDraft draft(CutDraft cuts) =>
        RegistrationDraft(workId: w, episodeId: ep, stages: ['LO'], cuts: cuts);
    register(store, draft(CutDraft(start: 12, count: 1)));
    final again = CutDraft(start: 12, count: 1, prefix: '', width: 1);
    // The grid sees it before saving, and the store refuses it.
    expect(again.clashes({'C012'}), {'12'});
    expect(() => register(store, draft(again)), throwsA(isA<CutNameClash>()));
    expect(store.cuts(ep).map((c) => c.number), ['C012']);
  });

  test('register writes a part, cuts, tasks per stage, splits and pairs', () {
    final store = fresh();
    final w = store.createWork('새벽의 정원');
    final ep = store.addEpisode(w, '#01');
    final cuts = CutDraft(count: 6)
      ..toggleRemoved(['C002'])
      ..toggleSplit(['C004'])
      ..toggleShared(['C005', 'C006'])
      ..add('BANK1');
    final due = DateTime(2026, 12, 20, 23, 59);
    register(
      store,
      RegistrationDraft(
        workId: w,
        episodeId: ep,
        partLabel: 'A',
        stages: ['LO', '원화'],
        cuts: cuts,
        dueAt: due,
      ),
    );
    final numbers = store.cuts(ep).map((c) => c.number).toList();
    expect(
      numbers,
      containsAll(['C001', 'C003', 'C004A', 'C004B', 'C005', 'C006', 'BANK1']),
    );
    expect(numbers, isNot(contains('C002')));
    final groups = store.partGroups();
    expect(groups.map((g) => g.stageName).toSet(), {'LO', '원화'});
    // Seven cuts, the shared pair C005-006 counting once (유저 2026-11-28).
    expect(groups.every((g) => g.total == 6), isTrue);
    expect(groups.every((g) => g.tasks.length == 7), isTrue);
    expect(groups.every((g) => g.dueAt!.isAtSameMomentAs(due)), isTrue);
  });

  test('names are matched by value, however they were typed', () {
    final store = fresh();
    final w = store.createWork('W');
    final ep = store.addEpisode(w, '#01');
    store.addCut(ep, 'C009');
    RegistrationDraft draft(CutDraft cuts) =>
        RegistrationDraft(workId: w, episodeId: ep, stages: ['LO'], cuts: cuts);
    // '9' is the cut already there.
    expect(
      () => register(store, draft(CutDraft(count: 1)..rename('C001', '9'))),
      throwsA(isA<CutNameClash>()),
    );
    // Typed 'c1' and 'c2' still split and pair as the grid said.
    register(
      store,
      draft(
        CutDraft(count: 3)
          ..rename('C001', 'c1')
          ..rename('C002', 'c2')
          ..toggleShared(['C001', 'C002'])
          ..toggleSplit(['C003']),
      ),
    );
    final rows = store.cuts(ep);
    expect(rows.map((c) => c.number), [
      'C001',
      'C002',
      'C003A',
      'C003B',
      'C009',
    ]);
    expect(rows.first.sharedLabel, 'C001-002');
  });

  test('an existing part label is reused; clashing names change nothing', () {
    final store = fresh();
    final w = store.createWork('별빛 정류장');
    final ep = store.addEpisode(w, '#08');
    register(
      store,
      RegistrationDraft(
        workId: w,
        episodeId: ep,
        partLabel: 'B',
        stages: ['원화'],
        cuts: CutDraft(count: 2),
      ),
    );
    register(
      store,
      RegistrationDraft(
        workId: w,
        episodeId: ep,
        partLabel: 'B',
        stages: ['원화'],
        cuts: CutDraft(start: 3, count: 2),
      ),
    );
    expect(store.parts(ep).length, 1);
    expect(store.partGroups().single.total, 4);
    expect(
      () => register(
        store,
        RegistrationDraft(
          workId: w,
          episodeId: ep,
          stages: ['원화'],
          cuts: CutDraft(count: 1),
        ),
      ),
      throwsA(isA<CutNameClash>()),
    );
    expect(store.cuts(ep).length, 4);
  });

  test('without a part every cut gets the deadline', () {
    final store = fresh();
    final w = store.createWork('별빛 정류장');
    final ep = store.addEpisode(w, '#08');
    final due = DateTime(2026, 12, 1, 23, 59);
    register(
      store,
      RegistrationDraft(
        workId: w,
        episodeId: ep,
        stages: ['원화'],
        cuts: CutDraft(start: 150, count: 3),
        dueAt: due,
      ),
    );
    final g = store.partGroups().single;
    expect(g.total, 3);
    expect(g.dueAt!.isAtSameMomentAs(due), isTrue);
  });

  test('a cut added past the run is its own cell; one inside it is not', () {
    final c = CutDraft(count: 3)
      ..add('C004')
      ..add('C003');
    expect(c.cells, ['C001', 'C002', 'C003', 'C004']);
  });

  test('taking out a mixed pick takes all out; an all-out pick comes back', () {
    final c = CutDraft(count: 3)..toggleRemoved(['C001']);
    c.toggleRemoved(['C001', 'C002']);
    expect(c.removed, {'C001', 'C002'});
    c.toggleRemoved(['C001', 'C002']);
    expect(c.removed, isEmpty);
  });
}
