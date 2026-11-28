import 'dart:io';

import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_codec.dart';
import 'package:anisched/src/services/document_files.dart';
import 'package:anisched/src/services/document_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android's SAF replace: the one document opened for writing and cut to
/// nothing first. [killed] makes the next replace die right after the
/// cut (유저 2026-11-28: the app force-stopped during a save left the
/// document at 0 bytes); [reportedSize] makes stat lie about the size.
class _StreamFiles extends PathDocumentFiles {
  bool killed = false;
  int replaces = 0;
  int? reportedSize;

  @override
  bool get replacesAtomically => false;

  @override
  Future<DocumentStat?> stat(DocumentRef ref) async {
    final s = await super.stat(ref);
    if (s == null || reportedSize == null) return s;
    return (size: reportedSize!, modifiedMs: s.modifiedMs);
  }

  @override
  Future<void> replaceFrom(String localPath, DocumentRef ref) async {
    replaces++;
    final target = File(ref.location)..writeAsBytesSync(const []);
    if (killed) {
      killed = false;
      throw StateError('process killed');
    }
    target.writeAsBytesSync(File(localPath).readAsBytesSync(), flush: true);
  }
}

void main() {
  late Directory tmp;
  late _StreamFiles files;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('anisched_safe');
    files = _StreamFiles();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(AppDatabase, DocumentSession)> start() async {
    final working = '${tmp.path}/app/anisched.db';
    Directory('${tmp.path}/app').createSync(recursive: true);
    final db = openAppDatabase(working);
    final session = await DocumentSession.open(
      writer: db,
      workingPath: working,
      folder: '${tmp.path}/app',
      files: files,
      autosaveDelay: const Duration(hours: 1),
    );
    return (db, session);
  }

  DocumentRef doc() => DocumentRef(
    location: '${tmp.path}/drive/일정.anisched',
    name: '일정.anisched',
  );

  Future<void> stop(AppDatabase db, DocumentSession session) async {
    await session.close();
    db.close();
  }

  test('a save killed after the cut is put right at the next start', () async {
    Directory('${tmp.path}/drive').createSync();
    var (db, session) = await start();
    CatalogueStore(db).addClient('회사');
    await session.saveAs(doc());
    CatalogueStore(db).addClient('두 번째');
    files.killed = true;
    await expectLater(session.save(), throwsStateError);
    expect(File(doc().location).lengthSync(), 0); // what the user found
    expect(session.dirty, isTrue);
    await stop(db, session);

    (db, session) = await start();
    expect(await session.resume(), isA<RemoteRepaired>());
    expect(File(doc().location).lengthSync(), greaterThan(0));
    // The repaired document opens, with what was being written.
    final check = '${tmp.path}/check.anisched';
    File(doc().location).copySync(check);
    await prepareImport(check);
    final opened = openAppDatabase('${tmp.path}/opened.db');
    importDocumentInto(opened, check);
    expect(CatalogueStore(opened).clients().map((c) => c.name), ['두 번째', '회사']);
    opened.close();
    await stop(db, session);
  });

  test('leaving the screen does not touch a document that is not replaced '
      'atomically; coming back saves it', () async {
    Directory('${tmp.path}/drive').createSync();
    final (db, session) = await start();
    await session.saveAs(doc());
    final before = files.replaces;
    CatalogueStore(db).addClient('회사');
    await session.flush();
    expect(files.replaces, before);
    expect(session.dirty, isTrue);
    expect(await session.resume(), isA<RemoteSame>());
    await session.flush(); // still not
    expect(files.replaces, before);
    await session.save(); // the autosave the return scheduled
    expect((files.replaces, session.dirty), (before + 1, false));
    await stop(db, session);
  });

  test('a write whose size does not come back stays unsaved', () async {
    Directory('${tmp.path}/drive').createSync();
    final (db, session) = await start();
    await session.saveAs(doc());
    CatalogueStore(db).addClient('회사');
    files.reportedSize = 7;
    await expectLater(
      session.save(),
      throwsA(isA<DocumentWriteMismatchException>()),
    );
    expect(session.dirty, isTrue);
    expect(session.lastSaveError, isA<DocumentWriteMismatchException>());
    files.reportedSize = null;
    await session.save();
    expect((session.dirty, session.lastSaveError), (false, null));
    await stop(db, session);
  });

  test('a document found empty on opening can be written back from the '
      'last write', () async {
    Directory('${tmp.path}/drive').createSync();
    final (db, session) = await start();
    CatalogueStore(db).addClient('회사');
    await session.saveAs(doc());
    await session.startUntitled();
    File(doc().location).writeAsBytesSync(const []);

    await expectLater(
      session.openDocument(doc()),
      throwsA(
        isA<NotADocumentException>().having(
          (e) => e.kind,
          'kind',
          NotADocumentKind.empty,
        ),
      ),
    );
    expect(session.hasLastWritten(doc()), isTrue);
    expect(await session.restoreLastWritten(doc()), isTrue);
    expect(CatalogueStore(db).clients().single.name, '회사');
    expect(session.document, doc());
    final other = DocumentRef(location: '${tmp.path}/x.anisched', name: 'x');
    expect(session.hasLastWritten(other), isFalse);
    expect(await session.restoreLastWritten(other), isFalse);
    await stop(db, session);
  });
}
