/// The web build has no background reader: isolates and native SQLite
/// are not there, so the app reads with [SyncCatalogueReader] on the one
/// thread it has (see `lib/boot_web.dart`).
library;

import 'catalogue_reader.dart';
