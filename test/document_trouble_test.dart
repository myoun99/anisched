import 'dart:io';

import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_files.dart';
import 'package:anisched/src/services/document_rows.dart';
import 'package:anisched/src/services/document_session.dart';
import 'package:anisched/src/services/schema.dart';
import 'package:anisched/src/ui/document_menu.dart';
import 'package:anisched/src/ui/document_trouble.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/text/strings.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens whatever it was given.
class _Picker implements DocumentPicker {
  const _Picker(this.ref);

  final DocumentRef ref;

  @override
  Future<DocumentRef?> pickOpen(BuildContext context) async => ref;

  @override
  Future<bool> saveAs(
    BuildContext context,
    DocumentSessionBase session,
    String suggestedName,
  ) async => false;
}

/// A button that shows [error]'s dialog, counting 「다시 시도」 taps.
Future<List<int>> pumpTrouble(WidgetTester t, Object error) async {
  final retries = [0];
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDocumentTrouble(
            context,
            error,
            retry: () async => retries[0]++,
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await t.tap(find.text('go'));
  await t.pump();
  return retries;
}

void main() {
  const ref = DocumentRef(location: '/x/a.anisched', name: 'a.anisched');
  final cases = <Object, DocumentTroubleKind>{
    DocumentUnreachableException(ref, 'permission revoked'):
        DocumentTroubleKind.unreachable,
    SchemaTooNewException(30, 20): DocumentTroubleKind.newer,
    NotADocumentException('a.anisched', 'not an Anisched document'):
        DocumentTroubleKind.notDocument,
    RemoteUnreachable(NotADocumentException('a.anisched', 'bad')):
        DocumentTroubleKind.notDocument,
    for (final k in [
      NotADocumentKind.damaged,
      NotADocumentKind.tablesDiffer,
      NotADocumentKind.migrateFailed,
    ])
      NotADocumentException('a.anisched', k.name, kind: k):
          DocumentTroubleKind.damaged,
    NotADocumentException('a.anisched', 'x', kind: NotADocumentKind.empty):
        DocumentTroubleKind.empty,
    NotADocumentException('a.anisched', 'x', kind: NotADocumentKind.foreignApp):
        DocumentTroubleKind.notDocument,
    const RemoteMissing(): DocumentTroubleKind.unreachable,
    StateError('boom'): DocumentTroubleKind.other,
  };
  for (final MapEntry(key: error, value: kind) in cases.entries) {
    testWidgets('$error reads as ${kind.name}', (t) async {
      await pumpTrouble(t, error);
      expect(DocumentTrouble.of(error).kind, kind);
      expect(find.text(kind.text), findsOneWidget);
      expect(find.byIcon(kind.icon), findsOneWidget);
      // The error as it came stays folded away.
      expect(find.byKey(const Key('doc-trouble-diagnosis')), findsNothing);
    });
  }

  test('every kind has its own line in every language', () {
    for (final lang in Lang.values) {
      appLang.value = lang;
      final lines = {for (final k in DocumentTroubleKind.values) k.text};
      expect(lines.length, DocumentTroubleKind.values.length);
    }
    appLang.value = Lang.ko;
  });

  testWidgets('자세히 shows the error as it came; copy puts it on the clipboard', (
    t,
  ) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final error = NotADocumentException('a.anisched', 'file is not a database');
    await pumpTrouble(t, error);
    await t.tap(find.byKey(const Key('doc-trouble-details')));
    await t.pump();
    expect(find.text('$error'), findsOneWidget);
    await t.tap(find.byKey(const Key('doc-trouble-copy')));
    await t.pump();
    expect(copied, '$error');
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('다시 시도 closes and runs the retry; 확인 only closes', (t) async {
    final retries = await pumpTrouble(t, StateError('x'));
    await t.tap(find.byKey(const Key('doc-trouble-retry')));
    await t.pump();
    expect(retries[0], 1);
    expect(find.byKey(const Key('doc-trouble')), findsNothing);
    await t.tap(find.text('go'));
    await t.pump();
    await t.tap(find.byKey(const Key('doc-trouble-ok')));
    await t.pump();
    expect(retries[0], 1);
    expect(find.byKey(const Key('doc-trouble')), findsNothing);
  });

  testWidgets('opening an empty file shows the dialog, not the raw error', (
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
    final empty = File('${tmp.path}/empty.anisched')..writeAsBytesSync([]);
    final store = CatalogueStore(db);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          reader: SyncCatalogueReader(store),
          store: store,
          session: session,
          picker: _Picker(
            DocumentRef(location: empty.path, name: 'empty.anisched'),
          ),
        ),
      ),
    );
    await t.pump();
    await t.tap(find.byKey(const Key('file-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('file-open')));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump();
    }
    expect(session.document, isNull);
    expect(find.byKey(const Key('doc-trouble')), findsOneWidget);
    expect(find.text(DocumentTroubleKind.empty.text), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byKey(const Key('doc-trouble-retry')), findsOneWidget);
  });
}
