import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// The registration lists: delete only what nothing uses (유저
/// 2026-11-28), and batches of writes for one user action.
void main() {
  late AppDatabase db;
  late CatalogueStore store;

  setUp(() {
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => DateTime(2026, 11, 28, 14));
  });

  tearDown(() => db.close());

  test('a client no work uses is deleted; one in use is refused', () {
    final free = store.addClient('빈 회사');
    final used = store.addClient('회사');
    store.createWork('작품', clientId: used);

    expect(store.inUse(CatalogueKind.client, free), isFalse);
    store.deleteClient(free);
    expect(store.clients().map((c) => c.name), ['회사']);
    expect(() => store.deleteClient(used), throwsStateError);
  });

  test('a work with an episode is refused; an empty one goes with its '
      'stages', () {
    final work = store.createWork('작품');
    final ep = store.addEpisode(work, '1');
    expect(() => store.deleteWork(work), throwsStateError);
    store.deleteEpisode(ep);
    store.deleteWork(work);
    expect(store.works(), isEmpty);
    expect(db.select('SELECT * FROM work_stages;'), isEmpty);
  });

  test('an episode or part whose only cut is archived is still in use', () {
    final work = store.createWork('작품');
    final ep = store.addEpisode(work, '1');
    final part = store.addPart(ep, 'A');
    final cut = store.addCuts(ep, ['1'], partId: part).added.single;
    store.archive(ArchiveKind.cut, cut);

    expect(store.inUse(CatalogueKind.episode, ep), isTrue);
    expect(store.inUse(CatalogueKind.part, part), isTrue);
    expect(() => store.deleteEpisode(ep), throwsStateError);
    expect(() => store.deletePart(part), throwsStateError);
    expect(store.episodes(work), hasLength(1));
  });

  test('the lists carry inUse, so a delete button can be dimmed first', () {
    final client = store.addClient('회사');
    final other = store.addClient('다른 회사');
    final work = store.createWork('작품', clientId: client);
    final empty = store.createWork('빈 작품');
    final ep = store.addEpisode(work, '1');
    final emptyEp = store.addEpisode(work, '2');
    final part = store.addPart(ep, 'A');
    final emptyPart = store.addPart(ep, 'B');
    store.addCuts(ep, ['1'], partId: part);

    expect(
      {for (final r in store.clients()) r.id: r.inUse},
      {client: true, other: false},
    );
    expect(
      {for (final r in store.searchClients('')) r.id: r.inUse},
      {client: true, other: false},
    );
    expect(
      {for (final r in store.works()) r.id: r.inUse},
      {work: true, empty: false},
    );
    expect(
      {for (final r in store.searchWorks('')) r.id: r.inUse},
      {work: true, empty: false},
    );
    expect(
      {for (final r in store.episodes(work)) r.id: r.inUse},
      {ep: true, emptyEp: false},
    );
    expect(
      {for (final r in store.parts(ep)) r.id: r.inUse},
      {part: true, emptyPart: false},
    );

    store
      ..deletePart(emptyPart)
      ..deleteEpisode(emptyEp)
      ..deleteWork(empty)
      ..deleteClient(other);
    expect(store.parts(ep).single.id, part);
  });

  test('a batch is one undo step, and all or nothing', () async {
    final history = UndoHistory.attach(db);
    addTearDown(history.detach);
    final work = store.createWork('작품');
    await Future<void>.value();
    history.clear();

    store.batch(() {
      store
        ..renameWork(work, '새 이름')
        ..setWorkClient(work, store.addClient('회사'));
    });
    await Future<void>.value();
    expect(store.works().single.title, '새 이름');
    history.undo();
    expect(store.works().single, (
      id: work,
      title: '작품',
      currency: 'JPY',
      clientId: null,
      inUse: false,
    ));
    expect(store.clients(), isEmpty);
    expect(history.canUndo, isFalse);

    expect(
      () => store.batch(() {
        store.renameWork(work, '반쯤');
        throw StateError('stop');
      }),
      throwsStateError,
    );
    expect(store.works().single.title, '작품');
  });
}
