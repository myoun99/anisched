import 'dart:io';

import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_files.dart';
import 'package:anisched/src/services/document_session.dart';
import 'package:anisched/src/ui/document_menu.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('untitled shows 무제; 저장 binds a file and shows its name', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final tmp = Directory.systemTemp.createTempSync('anisched-ui-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final working = '${tmp.path}/anisched.db';
    final db = openAppDatabase(working);
    addTearDown(db.close);
    final session = (await t.runAsync(
      () => DocumentSession.open(
        writer: db,
        workingPath: working,
        folder: tmp.path,
        files: const PathDocumentFiles(),
        autosaveDelay: const Duration(hours: 1),
      ),
    ))!;
    final store = CatalogueStore(db);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          reader: SyncCatalogueReader(store),
          store: store,
          session: session,
          picker: const PathPromptPicker(),
        ),
      ),
    );
    await t.pump();
    expect(find.text('무제'), findsOneWidget);

    await t.tap(find.byKey(const Key('file-menu')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('file-save-as')), findsOneWidget);
    expect(find.byKey(const Key('file-open')), findsOneWidget);
    await t.tapAt(const Offset(5, 700));
    await t.pumpAndSettle();

    final target = '${tmp.path}/cloud/일정';
    Directory('${tmp.path}/cloud').createSync();
    await t.runAsync(
      () => session.saveAs(
        DocumentRef(location: '$target.anisched', name: '일정.anisched'),
      ),
    );
    await t.pump();
    expect(session.document?.location, '$target.anisched');
    expect(File('$target.anisched').existsSync(), isTrue);
    expect(find.text('일정'), findsOneWidget);
  });
}
