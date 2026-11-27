import 'package:flutter/material.dart';

/// Placeholder shell until a design direction is chosen.
class AnischedApp extends StatelessWidget {
  const AnischedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anisched',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3B6EF5)),
      home: const Scaffold(body: Center(child: Text('Anisched'))),
    );
  }
}
