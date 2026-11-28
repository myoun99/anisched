import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Events of one card (유저 2026-11-28 정정): a part × stage, or the
/// part-less cuts of an episode × stage — not the whole episode.
void main() {
  final day = DateTime(2026, 12, 3);
  final from = DateTime(2026, 12);
  final to = DateTime(2027);
  late AppDatabase db;
  late CatalogueStore store;
  late int episode;
  late int part;
  late int lo;
  late int genga;
  late List<int> loTasks;

  setUp(() {
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => DateTime(2026, 11, 28, 14));
    final work = store.createWork('작품');
    final stages = {for (final s in store.stages(work)) s.name: s.id};
    lo = stages['LO']!;
    genga = stages['원화']!;
    episode = store.addEpisode(work, '1');
    part = store.addPart(episode, 'A');
    store.addCuts(episode, ['1', '2'], partId: part);
    loTasks = store.addTasksForPart(part, lo);
    store.addTasksForPart(part, genga);
  });

  tearDown(() => db.close());

  test('a card event shows on its card only, not on the same episode\'s '
      'other stage or as an episode event', () {
    final keys = {for (final g in store.partGroups()) g.key};
    expect(keys, {'part:$part:$lo', 'part:$part:$genga'});
    store
      ..addEvent(card: 'part:$part:$lo', date: day, title: '검수')
      ..addEvent(episodeId: episode, date: day, title: '아후레코');

    final cards = store.cardEvents(from: from, to: to);
    expect(cards.keys, ['part:$part:$lo']);
    final e = cards['part:$part:$lo']!.single;
    expect((e.title, e.episodeId, e.card), ('검수', episode, 'part:$part:$lo'));
    expect(store.events(from: from, to: to)[episode]!.map((e) => e.title), [
      '아후레코',
    ]);

    // Edited without naming the card again, it stays on its card.
    store.updateEvent(e.id, episodeId: episode, date: day, title: '검수 2');
    expect(
      store.cardEvents(from: from, to: to)['part:$part:$lo']!.single.title,
      '검수 2',
    );
  });

  test('a part-less card takes events too', () {
    store.addCuts(episode, ['9']);
    final loose = store.addTask(
      lo,
      cutId:
          db.select('SELECT id FROM cuts WHERE part_id IS NULL;').first['id']
              as int,
    );
    final key = 'nopart:$episode:$lo';
    expect(store.partGroups().map((g) => g.key), contains(key));
    store.addEvent(card: key, date: day, title: '러프 체크');
    expect(store.cardEvents(from: from, to: to)[key]!.single.title, '러프 체크');
    expect(store.events(from: from, to: to), isEmpty);
    expect(
      () => store.addEvent(card: 'storyboard:$loose', date: day, title: 'x'),
      throwsArgumentError,
    );

    store.deleteTasks([loose]);
    expect(store.cardEvents(from: from, to: to), isEmpty);
  });

  test('deleting a card\'s tasks takes its events, the other card keeps '
      'its own; undo brings them back', () async {
    final history = UndoHistory.attach(db);
    addTearDown(history.detach);
    store
      ..addEvent(card: 'part:$part:$lo', date: day, title: 'LO 검수')
      ..addEvent(card: 'part:$part:$genga', date: day, title: '원화 검수');
    await Future<void>.value();

    store.deleteTasks(loTasks);
    await Future<void>.value();
    expect(store.cardEvents(from: from, to: to).keys, ['part:$part:$genga']);

    history.undo();
    expect(store.cardEvents(from: from, to: to).keys, {
      'part:$part:$lo',
      'part:$part:$genga',
    });
  });
}
