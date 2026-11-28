import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;

import '../models/document.dart';

/// The web half of the document file: the browser's file picker brings a
/// document in (its bytes held here until the session reads them), and a
/// download takes one out. The working database itself stays in the
/// browser (IndexedDB), so nothing is lost between visits.
///
/// Writing straight back to a picked file (File System Access API) is
/// left for later: only Chromium browsers have it.

final _picked = <String, Uint8List>{};
var _next = 0;

/// Asks the user for a document to open; null when they backed out.
Future<DocumentRef?> pickDocument() async {
  final file = await file_selector.openFile(
    acceptedTypeGroups: const [
      file_selector.XTypeGroup(
        label: 'Anisched',
        extensions: [documentExtension],
      ),
    ],
  );
  if (file == null) return null;
  final location = 'upload:${_next++}';
  _picked[location] = await file.readAsBytes();
  return DocumentRef(location: location, name: file.name);
}

/// The bytes of a document [pickDocument] brought in (once), or null.
Future<Uint8List?> takePickedDocument(DocumentRef ref) async =>
    _picked.remove(ref.location);

/// Not used on the web: the session downloads the document itself.
Future<DocumentRef?> placeNewDocument(
  String stagedPath,
  String fileName,
) async => null;

/// Hands [bytes] to the browser as a download named [name].
void downloadDocument(String name, Uint8List bytes) {
  final blob = globalContext
      .getProperty<JSFunction>('Blob'.toJS)
      .callAsConstructor<JSObject>(
        [bytes.toJS].toJS,
        {'type': 'application/octet-stream'}.jsify(),
      );
  final url = globalContext
      .getProperty<JSObject>('URL'.toJS)
      .callMethod<JSString>('createObjectURL'.toJS, blob);
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final a = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS)
    ..['href'] = url
    ..['download'] = name.toJS;
  a.callMethod<JSAny?>('click'.toJS);
  globalContext
      .getProperty<JSObject>('URL'.toJS)
      .callMethod<JSAny?>('revokeObjectURL'.toJS, url);
}
