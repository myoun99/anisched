import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_rows.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = DateTime(2026, 11, 28, 14);
  late AppDatabase db;
  late CatalogueStore store;
  late UndoHistory history;
  late int part;
  late int lo;
  late List<int> tasks;

  /// One turn of the app: the writes, then the microtask that closes the
  /// step.
  Future<void> turn(void Function() writes) async {
    writes();
    await Future<void>.value();
  }

  /// Every row of the document, to compare states whole.
  String dump() => [
    for (final t in tableNames(db))
      '$t: ${db.select('SELECT rowid, * FROM "$t" ORDER BY rowid;').map((r) => r.values).toList()}',
  ].join('\n');

  DateTime? partDue() => store.partGroups().single.dueAt;

  setUp(() {
    now = DateTime(2026, 11, 28, 14);
    db = openAppDatabase(':memory:');
    store = CatalogueStore(db, clock: () => now);
    final work = store.createWork('작품');
    lo = store.stages(work).firstWhere((s) => s.name == 'LO').id;
    final episode = store.addEpisode(work, '1');
    part = store.addPart(episode, 'A');
    store.addCuts(episode, ['1', '2', '3'], partId: part);
    tasks = store.addTasksForPart(part, lo);
    store.setPartDue(part, lo, DateTime(2026, 12, 5));
    history = UndoHistory.attach(db);
  });

  tearDown(() async {
    await history.detach();
    db.close();
  });

  test('a deadline change undoes and redoes', () async {
    final before = dump();
    await turn(() => store.setPartDue(part, lo, DateTime(2026, 12, 9)));
    final after = dump();
    expect(partDue(), DateTime(2026, 12, 9).toUtc());
    expect(history.canUndo, isTrue);

    expect(history.undo(), isTrue);
    expect(dump(), before);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isTrue);

    expect(history.redo(), isTrue);
    expect(dump(), after);
    expect(history.canRedo, isFalse);
    expect(history.canUndo, isTrue);
  });

  test('one registration of many rows is one step', () async {
    final before = dump();
    await turn(() {
      final ep = store.addEpisode(store.works().single.id, '2');
      final p = store.addPart(ep, 'B');
      store
        ..addCuts(ep, [for (var i = 1; i <= 30; i++) '$i'], partId: p)
        ..addTasksForPart(p, lo);
    });
    expect(db.select('SELECT COUNT(*) AS n FROM tasks;').first['n'], 33);
    history.undo();
    expect(dump(), before);
    expect(history.canUndo, isFalse);
  });

  test('a deletion cascade comes back whole', () async {
    final at = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO work_intervals (started_at, stopped_at, task_id) '
      'VALUES (?, ?, ?);',
      [at, at + 600000, tasks.first],
    );
    final episode = db.select('SELECT id FROM episodes;').first['id'] as int;
    store
      ..extendDue(DueTarget.part(part, lo), DateTime(2026, 12, 7))
      ..pinLane('part:$part:$lo', 1)
      ..addEvent(episodeId: episode, date: now, title: '아후레코');
    history.clear();
    final before = dump();

    await turn(() => store.deleteTasks(tasks));
    expect(db.select('SELECT * FROM works;'), isEmpty);

    history.undo();
    expect(dump(), before);
    expect(db.select('PRAGMA foreign_key_check;'), isEmpty);
    history.redo();
    expect(db.select('SELECT * FROM works;'), isEmpty);
  });

  test('two changes of one row in a turn undo to where it began; a write '
      'that changes nothing is no step', () async {
    await turn(() {
      store
        ..setPartDue(part, lo, DateTime(2026, 12, 9))
        ..setPartDue(part, lo, DateTime(2026, 12, 12));
    });
    history.undo();
    expect(partDue(), DateTime(2026, 12, 5).toUtc());
    expect(history.canUndo, isFalse);

    await turn(() => store.setStatus(tasks.first, TaskStatus.received));
    expect(history.canUndo, isFalse);
  });

  test('a new write empties the redo stack', () async {
    await turn(() => store.setPartDue(part, lo, DateTime(2026, 12, 9)));
    history.undo();
    expect(history.canRedo, isTrue);
    await turn(() => store.setPartDue(part, lo, DateTime(2026, 12, 11)));
    expect(history.canRedo, isFalse);
    expect(history.redo(), isFalse);
    history.undo();
    expect(partDue(), DateTime(2026, 12, 5).toUtc());
  });

  test('the timer: start and stop are steps, its running and its target '
      'are not', () async {
    final timer = WorkTimerStore(db, clock: () => now);
    await turn(() => timer.start(taskId: tasks.first));
    expect(history.canUndo, isTrue);
    history.clear();

    now = now.add(const Duration(minutes: 30)); // ticks: reads only
    store
      ..taskRows()
      ..today();
    await turn(() => store.setTimerTarget(tasks.last));
    expect(history.canUndo, isFalse);

    await turn(timer.stop);
    expect(history.canUndo, isTrue);
    history.undo();
    expect(timer.running(), isNotNull);
    expect(store.timerTarget(), tasks.last);
  });

  test('replacing the document is no step and empties the history', () async {
    await turn(() => store.setPartDue(part, lo, DateTime(2026, 12, 9)));
    final other = openAppDatabase(':memory:');
    CatalogueStore(other).createWork('다른 작품');
    copyAllRows(other, db);
    other.close();
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(store.works().single.title, '다른 작품');
    // Recording goes on afterwards.
    await turn(() => store.createWork('셋째'));
    history.undo();
    expect(store.works().single.title, '다른 작품');
  });

  test('at most [limit] steps are kept, the oldest go first', () async {
    await history.detach();
    history = UndoHistory.attach(db, limit: 3);
    for (var day = 10; day < 15; day++) {
      await turn(() => store.setPartDue(part, lo, DateTime(2026, 12, day)));
    }
    var undone = 0;
    while (history.undo()) {
      undone++;
    }
    expect(undone, 3);
    expect(partDue(), DateTime(2026, 12, 11).toUtc());
  });
}
