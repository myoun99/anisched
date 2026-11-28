import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';

/// The database type on the web: the WebAssembly connection.
typedef AppDatabase = CommonDatabase;

/// IndexedDB has no shared memory for a write-ahead log; the app reads on
/// the same thread anyway.
const bool sqliteHasWal = false;

WasmSqlite3? _sqlite;
IndexedDbFileSystem? _store;
final _memory = InMemoryFileSystem(name: memoryVfs);

/// The in-memory file system that holds documents on their way in
/// (uploaded) and out (downloaded).
const String memoryVfs = 'anisched-memory';

/// Loads `sqlite3.wasm` (served beside index.html) and keeps databases in
/// IndexedDB [storeName]. Call once before [openSqlite].
Future<void> initSqlite({
  String wasmUrl = 'sqlite3.wasm',
  String storeName = 'anisched',
}) async {
  if (_sqlite != null) return;
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse(wasmUrl));
  final store = await IndexedDbFileSystem.open(dbName: storeName);
  sqlite
    ..registerVirtualFileSystem(store, makeDefault: true)
    ..registerVirtualFileSystem(_memory);
  _sqlite = sqlite;
  _store = store;
}

/// Waits until every write has reached IndexedDB (the page may go away).
Future<void> flushSqlite() async => _store?.flush();

WasmSqlite3 get _lib =>
    _sqlite ?? (throw StateError('initSqlite() has not finished.'));

/// Opens (or creates) the database at [path] in IndexedDB.
AppDatabase openSqlite(String path) => _lib.open(path);

/// Opens [path] in the in-memory file system.
CommonDatabase openMemoryFile(String path) => _lib.open(path, vfs: memoryVfs);

/// The bytes of an in-memory file, or null.
Uint8List? memoryFileBytes(String path) {
  if (_memory.xAccess(path, 0) == 0) return null;
  final file = _memory
      .xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READWRITE)
      .file;
  try {
    final out = Uint8List(file.xFileSize());
    file.xRead(out, 0);
    return out;
  } finally {
    file.xClose();
  }
}

/// Puts [bytes] in the in-memory file system at [path].
void putMemoryFile(String path, Uint8List bytes) {
  deleteMemoryFile(path);
  final file = _memory
      .xOpen(
        Sqlite3Filename(path),
        SqlFlag.SQLITE_OPEN_READWRITE | SqlFlag.SQLITE_OPEN_CREATE,
      )
      .file;
  try {
    file.xWrite(bytes, 0);
  } finally {
    file.xClose();
  }
}

/// Removes an in-memory file.
void deleteMemoryFile(String path) {
  if (_memory.xAccess(path, 0) != 0) _memory.xDelete(path, 0);
}
