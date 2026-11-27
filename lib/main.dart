import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/services/catalogue_store.dart';
import 'src/services/database.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final db = openAppDatabase('${dir.path}${Platform.pathSeparator}anisched.db');
  runApp(AnischedApp(store: CatalogueStore(db)));
}
