import 'package:flutter/material.dart';

import '../services/catalogue_store.dart';
import 'shell.dart';
import 'theme.dart';

class AnischedApp extends StatelessWidget {
  const AnischedApp({super.key, this.store});

  /// The user's catalogue; null shows empty views (widget tests).
  final CatalogueStore? store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anisched',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: AppShell(store: store),
    );
  }
}
