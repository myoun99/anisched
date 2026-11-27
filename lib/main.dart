import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/services/catalogue_reader.dart';
import 'src/services/database.dart';
import 'src/services/work_timer.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = '${dir.path}${Platform.pathSeparator}anisched.db';
  final db = openAppDatabase(path);
  // Views read on a background isolate; writes stay on this one.
  final reader = await BackgroundCatalogueReader.open(path, writer: db);
  AppLifecycleListener(
    onDetach: () {
      unawaited(reader.close());
      db.close();
    },
  );
  runApp(AnischedApp(reader: reader, timer: WorkTimerStore(db)));
}
