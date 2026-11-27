import 'dart:io';

import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/platform/documents.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_files.dart';
import 'package:anisched/src/services/document_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Map<String, Object?> Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(documentsChannel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(documentsChannel, null));

  const ref = DocumentRef(
    location: '/cloud/a.anisched',
    name: 'a.anisched',
    bookmark: 'b0',
  );
  const files = ChannelDocumentFiles();

  test('stat: size and time, missing, refusal', () async {
    answer((_) => {'status': 'granted', 'size': 12, 'modifiedMs': 34});
    expect(await files.stat(ref), (size: 12, modifiedMs: 34));
    expect(calls.single.arguments, {'location': '/cloud/a.anisched'});

    answer((_) => {'status': 'granted', 'size': 12});
    expect(await files.stat(ref), (size: 12, modifiedMs: null));

    answer((_) => {'status': 'missing'});
    expect(await files.stat(ref), isNull);

    answer((_) => {'status': 'unavailable', 'message': 'offline'});
    await expectLater(
      files.stat(ref),
      throwsA(
        isA<DocumentUnreachableException>().having(
          (e) => e.reason,
          'reason',
          'offline',
        ),
      ),
    );
  });

  test('reopen keeps what the runner does not restate', () async {
    answer((_) => {'status': 'granted'});
    final same = await files.reopen(ref);
    expect(same.location, ref.location);
    expect(same.bookmark, 'b0');

    answer(
      (_) => {
        'status': 'granted',
        'location': '/moved/a.anisched',
        'name': 'a.anisched',
        'bookmark': 'b1',
      },
    );
    final moved = await files.reopen(ref);
    expect(moved.location, '/moved/a.anisched');
    expect(moved.bookmark, 'b1');
  });

  test('read and replace name the paths; no runner is unreachable', () async {
    answer((_) => {'status': 'granted'});
    await files.readInto(ref, '/staging/in');
    await files.replaceFrom('/staging/out', ref);
    expect(calls.map((c) => c.method), ['readInto', 'replaceFrom']);
    expect(calls[0].arguments, {
      'location': ref.location,
      'destinationPath': '/staging/in',
    });
    expect(calls[1].arguments, {
      'location': ref.location,
      'sourcePath': '/staging/out',
    });

    messenger.setMockMethodCallHandler(documentsChannel, null);
    await expectLater(
      files.readInto(ref, '/x'),
      throwsA(isA<DocumentUnreachableException>()),
    );
  });

  test('Save As through a placer that moves the staged file', () async {
    final tmp = Directory.systemTemp.createTempSync('anisched_place');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = openAppDatabase('${tmp.path}/w.db');
    addTearDown(db.close);
    final session = await DocumentSession.open(
      writer: db,
      workingPath: '${tmp.path}/w.db',
      folder: tmp.path,
      files: const PathDocumentFiles(),
    );
    addTearDown(session.close);
    CatalogueStore(db).addClient('Studio');

    // Backed out: nothing bound, still dirty.
    expect(
      await session.saveAsPlaced((_, _) async => null, name: 'Mine'),
      isFalse,
    );
    expect(session.document, isNull);

    String? named;
    final saved = await session.saveAsPlaced((staged, fileName) async {
      named = fileName;
      final to = '${tmp.path}/$fileName';
      File(staged).renameSync(to); // what the iOS export picker does
      return DocumentRef(location: to, name: fileName);
    }, name: 'Mine');
    expect(saved, isTrue);
    expect(named, 'Mine.anisched');
    expect(session.document!.location, '${tmp.path}/Mine.anisched');
    expect(session.dirty, isFalse);
    expect(session.fingerprint!.modifiedMs, isNotNull);
  });
}
