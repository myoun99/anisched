import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/services/catalogue_reader.dart';
import 'src/services/catalogue_store.dart';
import 'src/services/database.dart';
import 'src/services/device_settings.dart';
import 'src/platform/documents.dart';
import 'src/services/document_session.dart';
import 'src/services/work_timer.dart';
import 'src/ui/app.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = '${dir.path}${Platform.pathSeparator}anisched.db';
  final db = openAppDatabase(path);
  // This device's own look (not in the document): theme, later language.
  final device = DeviceSettings.load(dir.path);
  themeModeSetting.value = switch (device.themeMode) {
    ThemeChoice.system => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };
  themeModeSetting.addListener(
    () => device.themeMode = switch (themeModeSetting.value) {
      ThemeMode.system => ThemeChoice.system,
      ThemeMode.light => ThemeChoice.light,
      ThemeMode.dark => ThemeChoice.dark,
    },
  );
  // Views read on a background isolate; writes stay on this one.
  final reader = await BackgroundCatalogueReader.open(path, writer: db);
  final session = await DocumentSession.open(
    writer: db,
    workingPath: path,
    folder: dir.path,
    files: platformDocumentFiles(),
  );
  final remote = ValueNotifier<RemoteCheck?>(null);
  // Save when the app leaves the screen; on return, take another device's
  // newer copy (or keep local work and snapshot theirs).
  AppLifecycleListener(
    onHide: () => unawaited(session.flush()),
    onPause: () => unawaited(session.flush()),
    onResume: () async => remote.value = await session.resume(),
    onDetach: () {
      unawaited(
        session.flush().whenComplete(() async {
          await reader.close();
          db.close();
        }),
      );
    },
  );
  unawaited(session.resume().then((r) => remote.value = r));
  runApp(
    AnischedApp(
      reader: reader,
      store: CatalogueStore(db),
      timer: WorkTimerStore(db),
      session: session,
      remote: remote,
    ),
  );
}
