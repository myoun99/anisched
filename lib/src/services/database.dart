import 'schema.dart';
import 'sqlite_backend.dart';

export 'sqlite_backend.dart' show AppDatabase, initSqlite;

/// Opens the app's single SQLite file and migrates it to the latest schema.
/// WAL keeps reads off the writer's lock, which matters once the timeline
/// scrolls while a timer ticks (devices; the web has no WAL and reads on
/// the same thread).
AppDatabase openAppDatabase(String path) {
  final db = openSqlite(path);
  if (sqliteHasWal) db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA foreign_keys = ON;');
  migrate(db);
  return db;
}
