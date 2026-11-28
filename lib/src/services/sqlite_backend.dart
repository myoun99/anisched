/// Where SQLite comes from — the one fork between devices and the web.
///
/// Devices use the native library through FFI (`package:sqlite3/sqlite3.dart`);
/// the web build uses the WebAssembly build (`web/sqlite3.wasm`) with the
/// database kept in the browser's IndexedDB. Everything else talks to the
/// shared `CommonDatabase` API (`package:sqlite3/common.dart`).
library;

export 'sqlite_backend_io.dart'
    if (dart.library.js_interop) 'sqlite_backend_web.dart';
