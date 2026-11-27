import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/catalogue_reader.dart';
import '../services/catalogue_store.dart';
import '../services/document_session.dart';
import '../services/work_timer.dart';
import 'shell.dart';
import 'theme.dart';

class AnischedApp extends StatelessWidget {
  const AnischedApp({
    super.key,
    this.reader,
    this.store,
    this.timer,
    this.session,
    this.remote,
  });

  /// Reads the user's catalogue; null shows empty views (widget tests).
  final CatalogueReader? reader;

  /// Writes (status changes); null keeps the app read-only.
  final CatalogueStore? store;

  /// The work timer's store.
  final WorkTimerStore? timer;

  /// The open document; null hides the file menu.
  final DocumentSession? session;

  /// The last resume check.
  final ValueListenable<RemoteCheck?>? remote;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeSetting,
      builder: (context, mode, _) => MaterialApp(
        themeMode: mode,
        themeAnimationDuration: Duration.zero,
        title: 'Anisched',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        scrollBehavior: const AlwaysScrollbarBehavior(),
        home: AppShell(
          reader: reader,
          store: store,
          timer: timer,
          session: session,
          remote: remote,
        ),
      ),
    );
  }
}
