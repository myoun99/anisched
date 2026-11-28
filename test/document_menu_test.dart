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
  saveAsTests();
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

  for (final browser in [false, true]) {
    testWidgets('the menu words (browser: $browser)', (t) async {
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
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentMenu(
              session: session,
              picker: const PathPromptPicker(),
              browser: browser,
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('file-menu')));
      await t.pumpAndSettle();
      expect(find.text('파일로 내보내기'), browser ? findsOneWidget : findsNothing);
      expect(find.text('파일 열기'), browser ? findsOneWidget : findsNothing);
      expect(find.text('저장'), browser ? findsNothing : findsOneWidget);
      expect(find.text('열기'), browser ? findsNothing : findsOneWidget);
    });
  }
}

/// Remembers the name Save As was asked for.
class _NamePicker implements DocumentPicker {
  String? asked;

  @override
  Future<DocumentRef?> pickOpen(BuildContext context) async => null;

  @override
  Future<bool> saveAs(
    BuildContext context,
    DocumentSessionBase session,
    String suggestedName,
  ) async {
    asked = suggestedName;
    return false;
  }
}

void saveAsTests() {
  test('a typed name is the file\'s, its extension taken off', () {
    expect(saveAsName(' abc.anisched '), 'abc');
    expect(saveAsName('abc.ANISCHED'), 'abc');
    expect(saveAsName('11월 일정'), '11월 일정');
  });

  testWidgets('Save As asks the name first: no extension in the field', (
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
    final picker = _NamePicker();
    final store = CatalogueStore(db);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          reader: SyncCatalogueReader(store),
          store: store,
          session: session,
          picker: picker,
        ),
      ),
    );
    await t.pump();
    await t.tap(find.byKey(const Key('file-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('file-save-as')));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byKey(const Key('name-input')));
    expect(field.controller!.text, '무제', reason: 'the name, no extension');
    expect(field.decoration!.suffixText, '.anisched', reason: 'shown faint');
    await t.enterText(find.byKey(const Key('name-input')), 'abc.anisched');
    await t.tap(find.byKey(const Key('name-ok')));
    await t.pumpAndSettle();
    expect(picker.asked, 'abc.anisched', reason: 'one extension, not two');
  });
}
