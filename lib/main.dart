import 'dart:async';

import 'package:flutter/material.dart';

import 'boot.dart';
import 'src/services/catalogue_store.dart';
import 'src/services/device_settings.dart';
import 'src/services/document_session.dart';
import 'src/services/sample_data.dart';
import 'src/services/work_timer.dart';
import 'src/ui/app.dart';
import 'src/ui/app_start.dart';
import 'src/ui/text/strings.dart';
import 'src/ui/theme.dart';
import 'src/ui/undo.dart';
import 'src/ui/views/chart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The name and a spinner first; the app once everything is ready.
  runApp(const AppStart(load: _start));
}

Future<Widget> _start() async {
  final (:db, :reader, :session, :device) = await boot();
  // This device's own look (not in the document): theme and language.
  languageSetting.value = device.language;
  appLang.value = resolveLang(
    device.language,
    WidgetsBinding.instance.platformDispatcher.locales,
  );
  languageSetting.addListener(() => device.language = languageSetting.value);
  // This device's keys for undo and redo (settings can change them).
  shortcutKeys.value = device.shortcuts(apple: appleKeys);
  saveShortcut = (action, keys) {
    device.setShortcut(action, keys);
    shortcutKeys.value = device.shortcuts(apple: appleKeys);
  };
  // The charts' month view, as this device last left it.
  chartMonthView.value = device.monthView;
  chartMonthView.addListener(() => device.monthView = chartMonthView.value);
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
  return AnischedApp(
    reader: reader,
    store: CatalogueStore(db),
    timer: WorkTimerStore(db),
    session: session,
    remote: remote,
    // An empty document offers the example catalogue (first run).
    onSample: (store) => fillSample(store, DateTime.now()),
  );
}
