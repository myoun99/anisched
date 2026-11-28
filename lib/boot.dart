/// What the app needs before its first frame, made the device's way
/// (`boot_io.dart`: files in the app container, a background reader) or
/// the browser's (`boot_web.dart`: SQLite in WebAssembly over IndexedDB,
/// reads on the one thread). `main.dart` is the same for both.
library;

import 'package:sqlite3/common.dart';

import 'src/services/catalogue_reader.dart';
import 'src/services/device_settings.dart';
import 'src/services/document_session.dart';

export 'boot_io.dart' if (dart.library.js_interop) 'boot_web.dart';

/// The working database, its reader, the document session and this
/// device's own settings.
typedef Booted = ({
  CommonDatabase db,
  CatalogueReader reader,
  DocumentSessionBase session,
  DeviceSettings device,
});
