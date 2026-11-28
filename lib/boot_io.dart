import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'boot.dart';
import 'src/platform/documents.dart';
import 'src/services/catalogue_reader.dart';
import 'src/services/database.dart';
import 'src/services/device_settings.dart';
import 'src/services/document_session.dart';
import 'src/services/undo_history.dart';

/// Devices: the working file and state in the app support folder; views
/// read on a background isolate while writes stay on this one.
Future<Booted> boot() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = '${dir.path}${Platform.pathSeparator}anisched.db';
  final db = openAppDatabase(path);
  final reader = await BackgroundCatalogueReader.open(path, writer: db);
  final session = await DocumentSession.open(
    writer: db,
    workingPath: path,
    folder: dir.path,
    files: platformDocumentFiles(),
  );
  // Every write from here on can be undone (UndoHistory.of(db)).
  UndoHistory.attach(db);
  return (
    db: db,
    reader: reader,
    session: session,
    device: loadDeviceSettings(dir.path),
  );
}
