import 'package:flutter/material.dart';

import 'shell.dart';
import 'theme.dart';

class AnischedApp extends StatelessWidget {
  const AnischedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anisched',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: const AppShell(),
    );
  }
}
