/// The platform half of the document file (docs/storage.md). Devices: the
/// runner's channel or file dialogs and real paths (`documents_io.dart`);
/// the web build: upload and download (`documents_web.dart`). Both give
/// [pickDocument] and [placeNewDocument].
library;

export 'documents_io.dart' if (dart.library.js_interop) 'documents_web.dart';
