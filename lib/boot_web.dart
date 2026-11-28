import 'boot.dart';
import 'src/platform/documents_web.dart';
import 'src/services/catalogue_reader.dart';
import 'src/services/catalogue_store.dart';
import 'src/services/database.dart';
import 'src/services/device_settings_web.dart';
import 'src/services/document_session_web.dart';
import 'src/services/undo_history.dart';

/// The web build (previews and feedback): SQLite in WebAssembly with the
/// working database in this browser's IndexedDB; reads on the one thread
/// there is; documents come in by upload and go out by download.
Future<Booted> boot() async {
  await initSqlite();
  final db = openAppDatabase('/anisched.db');
  // Every write from here on can be undone (UndoHistory.of(db)).
  UndoHistory.attach(db);
  return (
    db: db,
    reader: SyncCatalogueReader(CatalogueStore(db)),
    session: BrowserDocumentSession(
      writer: db,
      read: takePickedDocument,
      download: downloadDocument,
    ),
    device: loadDeviceSettings('anisched.'),
  );
}
