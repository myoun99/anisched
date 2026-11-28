import 'package:sqlite3/sqlite3.dart';

/// The database type on devices: the native connection.
typedef AppDatabase = Database;

/// Whether the backend keeps a write-ahead log (readers beside the writer).
const bool sqliteHasWal = true;

/// Nothing to load on devices: the library is linked in.
Future<void> initSqlite() async {}

/// Opens (or creates) the database file at [path].
AppDatabase openSqlite(String path) => sqlite3.open(path);
