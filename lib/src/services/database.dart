import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// Opens the app's single SQLite file and migrates it to the latest schema.
/// WAL keeps reads off the writer's lock, which matters once the timeline
/// scrolls while a timer ticks.
Database openAppDatabase(String path) {
  final db = sqlite3.open(path)
    ..execute('PRAGMA journal_mode = WAL;')
    ..execute('PRAGMA foreign_keys = ON;');
  migrate(db);
  return db;
}
