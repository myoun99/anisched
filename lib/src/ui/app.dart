import 'package:flutter/material.dart';

import '../services/catalogue_reader.dart';
import '../services/catalogue_store.dart';
import '../services/work_timer.dart';
import 'shell.dart';
import 'theme.dart';

class AnischedApp extends StatelessWidget {
  const AnischedApp({super.key, this.reader, this.store, this.timer});

  /// Reads the user's catalogue; null shows empty views (widget tests).
  final CatalogueReader? reader;

  /// Writes (status changes); null keeps the app read-only.
  final CatalogueStore? store;

  /// The work timer's store.
  final WorkTimerStore? timer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anisched',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: AppShell(reader: reader, store: store, timer: timer),
    );
  }
}
