import 'dart:async';
import 'dart:io';

import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_codec.dart';
import 'package:anisched/src/services/document_rows.dart';
import 'package:anisched/src/services/document_files.dart';
import 'package:anisched/src/services/document_session.dart';
import 'package:anisched/src/services/recovery_snapshots.dart';
import 'package:anisched/src/services/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// One device: its own app container, working database and session.
class Device {
  Device._(this.folder, this.db, this.session);

  static Future<Device> start(
    String folder, {
    Duration autosaveDelay = const Duration(hours: 1),
    DateTime Function()? clock,
  }) async {
    Directory(folder).createSync(recursive: true);
    final working = '$folder/anisched.db';
    final db = openAppDatabase(working);
    final session = await DocumentSession.open(
      writer: db,
      workingPath: working,
      folder: folder,
      files: const PathDocumentFiles(),
      autosaveDelay: autosaveDelay,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
    return Device._(folder, db, session);
  }

  final String folder;
  final Database db;
  final DocumentSession session;

  CatalogueStore get store => CatalogueStore(db);

  List<String> get clientNames => [for (final c in store.clients()) c.name];

  Future<void> stop() async {
    await session.close();
    db.close();
  }
}

/// Real files, but the replace waits for [gate] — a save held open.
class _GatedFiles extends PathDocumentFiles {
  _GatedFiles(this.gate);

  final Future<void> gate;
  static bool waiting = false;

  @override
  Future<void> replaceFrom(String localPath, DocumentRef ref) async {
    waiting = true;
    await gate;
    await super.replaceFrom(localPath, ref);
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('anisched_doc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  DocumentRef refAt(String name) =>
      DocumentRef(location: '${tmp.path}/cloud/$name', name: name);

  setUp(() => Directory('${tmp.path}/cloud').createSync());

  group('codec', () {
    // The web build moves documents with these two between connections
    // that cannot ATTACH each other (IndexedDB, in-memory files); here they
    // run on native connections, the same SQL.
    test('rows copy between connections: every table, nothing seeded', () {
      final from = openAppDatabase(':memory:');
      final to = openAppDatabase(':memory:');
      addTearDown(from.close);
      addTearDown(to.close);
      final store = CatalogueStore(from);
      final w = store.createWork('W');
      store.addEpisodeWithCuts(w, '#1', 'C1~C3');
      store.settings.cutStyle = (prefix: '', digits: 4);
      CatalogueStore(to).createWork('only in the target');
      copyAllRows(from, to);
      for (final t in tableNames(from)) {
        expect(
          to.select('SELECT * FROM "$t"').map((r) => r.values.toString()),
          from.select('SELECT * FROM "$t"').map((r) => r.values.toString()),
          reason: t,
        );
      }
      expect(CatalogueStore(to).works().single.title, 'W');
    });

    test('only an Anisched document passes the check', () {
      final stray = sqlite3.openInMemory();
      addTearDown(stray.close);
      expect(
        () => checkAndMigrateDocument(stray, 'stray'),
        throwsA(isA<NotADocumentException>()),
      );
      final other = sqlite3.openInMemory()..execute('CREATE TABLE x (y)');
      addTearDown(other.close);
      expect(
        () => copyAllRows(other, openAppDatabase(':memory:')),
        throwsA(isA<NotADocumentException>()),
      );
    });

    test('export is one rollback-journal file stamped as a document', () async {
      final db = openAppDatabase('${tmp.path}/w.db');
      CatalogueStore(db).addClient('Studio A');
      final out = '${tmp.path}/cloud/a.anisched';
      final content = await exportDocument('${tmp.path}/w.db', out);
      db.close();

      expect(Directory('${tmp.path}/cloud').listSync().map((e) => e.path), [
        out,
      ]);
      expect(content.size, File(out).lengthSync());
      expect(content.hash, hashFileSync(out));
      final doc = sqlite3.open(out, mode: OpenMode.readOnly);
      expect(doc.select('PRAGMA journal_mode').first.columnAt(0), 'delete');
      expect(
        doc.select('PRAGMA application_id').first.columnAt(0),
        documentApplicationId,
      );
      expect(
        doc.select('PRAGMA user_version').first.columnAt(0),
        latestSchemaVersion,
      );
      doc.close();
    });

    test('import replaces every row and keeps connections valid', () async {
      final a = openAppDatabase('${tmp.path}/a.db');
      CatalogueStore(a).addClient('From A');
      await exportDocument('${tmp.path}/a.db', '${tmp.path}/doc.anisched');
      a.close();

      final b = openAppDatabase('${tmp.path}/b.db');
      final store = CatalogueStore(b)..addClient('Only B');
      final reader = await BackgroundCatalogueReader.open(
        '${tmp.path}/b.db',
        writer: b,
      );
      expect((await reader.clients()).map((c) => c.name), ['Only B']);
      final generation = reader.generation;

      await prepareImport('${tmp.path}/doc.anisched');
      importDocumentInto(b, '${tmp.path}/doc.anisched');

      expect(store.clients().map((c) => c.name), ['From A']);
      expect(reader.generation, greaterThan(generation));
      expect((await reader.clients()).map((c) => c.name), ['From A']);
      // Presets survived the wholesale replace.
      expect(store.presets(), isNotEmpty);
      await reader.close();
      b.close();
    });

    test('refuses files that are not documents', () async {
      final text = File('${tmp.path}/x.anisched')..writeAsStringSync('hello');
      expect(
        () => prepareImport(text.path),
        throwsA(isA<NotADocumentException>()),
      );
      final other = sqlite3.open('${tmp.path}/other.db')
        ..execute('CREATE TABLE t (x)');
      other.close();
      expect(
        () => prepareImport('${tmp.path}/other.db'),
        throwsA(isA<NotADocumentException>()),
      );
    });

    test('refuses a document from a newer app', () async {
      final path = '${tmp.path}/new.anisched';
      createEmptyDocumentSync(path);
      sqlite3.open(path)
        ..execute('PRAGMA user_version = ${latestSchemaVersion + 1}')
        ..close();
      expect(() => prepareImport(path), throwsA(isA<SchemaTooNewException>()));
    });

    test('an older document is migrated on the way in', () async {
      final path = '${tmp.path}/old.anisched';
      final old = sqlite3.open(path)
        ..execute('PRAGMA application_id = $documentApplicationId');
      migrate(old, steps: migrations.take(2).toList());
      old.close();
      await prepareImport(path);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      expect(
        db.select('PRAGMA user_version').first.columnAt(0),
        latestSchemaVersion,
      );
      db.close();
    });
  });

  group('session', () {
    test('untitled saves nothing until Save As, then binds', () async {
      final d = await Device.start('${tmp.path}/d1');
      d.store.addClient('Studio A');
      await pumpEventQueue();
      expect(d.session.dirty, isTrue);
      await d.session.flush();
      expect(Directory('${tmp.path}/cloud').listSync(), isEmpty);

      final ref = refAt('mine.anisched');
      await d.session.saveAs(ref);
      expect(d.session.document, ref);
      expect(d.session.dirty, isFalse);
      expect(d.session.recents.single.ref, ref);
      expect(File(ref.location).existsSync(), isTrue);
      expect(d.session.fingerprint!.hash, hashFileSync(ref.location));
      await d.stop();
    });

    test('autosaves a moment after the last edit', () async {
      final d = await Device.start(
        '${tmp.path}/d1',
        autosaveDelay: const Duration(milliseconds: 30),
      );
      final ref = refAt('auto.anisched');
      await d.session.saveAs(ref);
      final before = hashFileSync(ref.location);

      d.store.addClient('Studio B');
      await pumpEventQueue();
      expect(d.session.dirty, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await d.session.flush(); // waits for the job in flight
      expect(d.session.dirty, isFalse);
      expect(hashFileSync(ref.location), isNot(before));
      await d.stop();
    });

    test('state survives a relaunch, unsaved edits included', () async {
      var d = await Device.start('${tmp.path}/d1');
      final ref = refAt('keep.anisched');
      await d.session.saveAs(ref);
      d.store.addClient('Unsaved');
      await pumpEventQueue();
      await d.stop(); // killed before the autosave

      d = await Device.start('${tmp.path}/d1');
      expect(d.session.document, ref);
      expect(d.session.dirty, isTrue);
      expect(d.clientNames, ['Unsaved']);
      await d.session.flush();
      expect(d.session.dirty, isFalse);
      await d.stop();
    });

    test('another device opens the same file and sees the work', () async {
      final a = await Device.start('${tmp.path}/a');
      a.store.addClient('Studio A');
      final ref = refAt('shared.anisched');
      await a.session.saveAs(ref);

      final b = await Device.start('${tmp.path}/b');
      b.store.addClient('Scratch on B');
      await pumpEventQueue();
      final changes = <DocumentChange>[];
      b.session.changes.listen(changes.add);
      await b.session.openDocument(ref);
      expect(b.clientNames, ['Studio A']);
      expect(changes, contains(DocumentChange.content));
      expect(b.session.dirty, isFalse);
      // B's untitled scratch was not thrown away.
      final kept = b.session.snapshots.list().single;
      expect(kept.reason, SnapshotReason.beforeReplace);
      await a.stop();
      await b.stop();
    });

    test('resume reloads what another device saved when clean', () async {
      final a = await Device.start('${tmp.path}/a');
      final ref = refAt('shared.anisched');
      await a.session.saveAs(ref);
      final b = await Device.start('${tmp.path}/b');
      await b.session.openDocument(ref);
      expect(await b.session.resume(), isA<RemoteSame>());

      a.store.addClient('Added on A');
      await a.session.flush();
      final result = await b.session.resume();
      expect(result, isA<RemoteReloaded>());
      expect(b.clientNames, ['Added on A']);
      expect(await b.session.resume(), isA<RemoteSame>());
      await a.stop();
      await b.stop();
    });

    test(
      'resume keeps local edits and the other version, then overwrites',
      () async {
        final a = await Device.start('${tmp.path}/a');
        final ref = refAt('shared.anisched');
        await a.session.saveAs(ref);
        final b = await Device.start('${tmp.path}/b');
        await b.session.openDocument(ref);

        a.store.addClient('From A');
        await a.session.flush();
        b.store.addClient('From B');
        await pumpEventQueue();

        final result = await b.session.resume();
        expect(result, isA<RemoteKeptLocal>());
        final snapshot = (result as RemoteKeptLocal).snapshot;
        expect(snapshot.reason, SnapshotReason.overwritten);
        expect(b.clientNames, ['From B']);

        await b.session.flush(); // last writer wins
        expect(await a.session.resume(), isA<RemoteReloaded>());
        expect(a.clientNames, ['From B']);

        // A's version is still recoverable on B.
        await b.session.restoreSnapshot(snapshot.path);
        expect(b.clientNames, ['From A']);
        expect(b.session.dirty, isTrue);
        await a.stop();
        await b.stop();
      },
    );

    test('a touched file with the same bytes is not a change', () async {
      final d = await Device.start('${tmp.path}/d1');
      final ref = refAt('t.anisched');
      await d.session.saveAs(ref);
      File(ref.location).setLastModifiedSync(DateTime(2030));
      expect(await d.session.resume(), isA<RemoteSame>());
      expect(
        d.session.fingerprint!.modifiedMs,
        DateTime(2030).millisecondsSinceEpoch,
      );
      await d.stop();
    });

    test('a missing document is reported, not forgotten', () async {
      final d = await Device.start('${tmp.path}/d1');
      final ref = refAt('gone.anisched');
      await d.session.saveAs(ref);
      File(ref.location).deleteSync();
      expect(await d.session.resume(), isA<RemoteMissing>());
      expect(d.session.document, ref);
      await d.stop();
    });

    test('a failed open changes nothing', () async {
      final d = await Device.start('${tmp.path}/d1');
      d.store.addClient('Keep');
      File('${tmp.path}/cloud/bad.anisched').writeAsStringSync('nope');
      await expectLater(
        d.session.openDocument(refAt('bad.anisched')),
        throwsA(isA<NotADocumentException>()),
      );
      await expectLater(
        d.session.openDocument(refAt('absent.anisched')),
        throwsA(isA<DocumentUnreachableException>()),
      );
      expect(d.clientNames, ['Keep']);
      expect(d.session.document, isNull);
      await d.stop();
    });

    test('new untitled empties the catalogue and unbinds', () async {
      final d = await Device.start('${tmp.path}/d1');
      await d.session.saveAs(refAt('x.anisched'));
      d.store.addClient('Saved');
      await pumpEventQueue();
      await d.session.startUntitled();
      expect(d.clientNames, isEmpty);
      expect(d.store.presets(), isNotEmpty);
      expect(d.session.document, isNull);
      expect(d.session.dirty, isFalse);
      // The dirty edit went to the bound file before it was let go.
      final other = await Device.start('${tmp.path}/d2');
      await other.session.openDocument(refAt('x.anisched'));
      expect(other.clientNames, ['Saved']);
      await d.stop();
      await other.stop();
    });

    test('an edit made while a save runs keeps the session dirty', () async {
      final gate = Completer<void>();
      final folder = '${tmp.path}/g';
      Directory(folder).createSync(recursive: true);
      final db = openAppDatabase('$folder/anisched.db');
      addTearDown(db.close);
      final session = await DocumentSession.open(
        writer: db,
        workingPath: '$folder/anisched.db',
        folder: folder,
        files: _GatedFiles(gate.future),
        autosaveDelay: const Duration(hours: 1),
      );
      addTearDown(session.close);
      final ref = refAt('g.anisched');
      CatalogueStore(db).addClient('Before');
      final saving = session.saveAs(ref);
      await pumpEventQueue();
      while (!_GatedFiles.waiting) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      CatalogueStore(db).addClient('During');
      gate.complete();
      await saving;
      expect(session.dirty, isTrue);
    });

    test('snapshots older than 30 days are removed at start', () async {
      var now = DateTime.utc(2026, 11, 1);
      final folder = '${tmp.path}/d1';
      final d = await Device.start(folder, clock: () => now);
      await d.session.snapshots.takeOf(
        '$folder/anisched.db',
        SnapshotReason.beforeReplace,
      );
      now = DateTime.utc(2026, 11, 5, 12); // 29½ days before the restart
      await d.session.snapshots.takeOf(
        '$folder/anisched.db',
        SnapshotReason.beforeReplace,
      );
      expect(d.session.snapshots.list(), hasLength(2));
      await d.stop();

      now = DateTime.utc(2026, 12, 5);
      final again = await Device.start(folder, clock: () => now);
      final left = again.session.snapshots.list();
      expect(left.single.takenAt, DateTime.utc(2026, 11, 5, 12));
      await again.stop();
    });
  });

  test('a large catalogue saves and opens quickly', () async {
    final a = openAppDatabase('${tmp.path}/a.db');
    final store = CatalogueStore(a);
    for (var i = 0; i < 3; i++) {
      final w = store.createWork('W$i');
      final r = store.addEpisodeWithCuts(
        w,
        '#1',
        'C0001~C1500',
        partLabel: 'A',
      );
      for (final name in ['LO', '원화']) {
        store.addTasksForPart(
          r.partId!,
          store.stages(w).firstWhere((s) => s.name == name).id,
        );
      }
    }
    final sw = Stopwatch()..start();
    final content = await exportDocument(
      '${tmp.path}/a.db',
      '${tmp.path}/big.anisched',
    );
    final tExport = sw.elapsedMilliseconds;
    await prepareImport('${tmp.path}/big.anisched');
    final tPrepare = sw.elapsedMilliseconds - tExport;
    final b = openAppDatabase('${tmp.path}/b.db');
    importDocumentInto(b, '${tmp.path}/big.anisched');
    final tImport = sw.elapsedMilliseconds - tExport - tPrepare;
    expect(
      b.select('SELECT COUNT(*) FROM tasks').first.columnAt(0),
      3 * 1500 * 2,
    );
    // ignore: avoid_print
    print(
      '9000 tasks, ${content.size >> 10} KiB: export ${tExport}ms, '
      'check ${tPrepare}ms, import ${tImport}ms (main isolate)',
    );
    expect(sw.elapsedMilliseconds, lessThan(10000));
    a.close();
    b.close();
  });

  test('recents keep the newest first, without duplicates', () {
    final t = DateTime.utc(2026);
    var list = <RecentDocument>[];
    for (var i = 0; i < 12; i++) {
      list = touchRecent(list, DocumentRef(location: '/f$i', name: 'f$i'), t);
    }
    list = touchRecent(list, const DocumentRef(location: '/f5', name: 'f5'), t);
    expect(list, hasLength(maxRecentDocuments));
    expect(list.first.ref.location, '/f5');
    expect(list.where((r) => r.ref.location == '/f5'), hasLength(1));
  });
}
