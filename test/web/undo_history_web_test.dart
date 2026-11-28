@TestOn('browser')
library;

import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// The undo history on the browser's SQLite (WebAssembly): run with
///   flutter test --platform chrome test/web
void main() {
  test('undo and redo on the web backend', () async {
    // test/web/sqlite3.wasm links to the build's web/sqlite3.wasm.
    await initSqlite(); // loads sqlite3.wasm beside the test page
    final db = openAppDatabase('/undo-test.db');
    final store = CatalogueStore(db);
    final history = UndoHistory.attach(db);
    store.createWork('작품');
    await Future<void>.value();
    expect(store.works(), hasLength(1));
    history.undo();
    expect(store.works(), isEmpty);
    history.redo();
    expect(store.works().single.title, '작품');
    // A deletion cascade, back whole (deferred foreign keys there too).
    final work = store.works().single.id;
    final lo = store.stages(work).first.id;
    final ep = store.addEpisode(work, '1');
    final part = store.addPart(ep, 'A');
    store.addCuts(ep, ['1', '2'], partId: part);
    final tasks = store.addTasksForPart(part, lo);
    await Future<void>.value();
    store.deleteTasks(tasks);
    await Future<void>.value();
    expect(store.works(), isEmpty);
    history.undo();
    expect(store.partGroups().single.tasks.map((t) => t.id), tasks);
    await history.detach();
  });
}
