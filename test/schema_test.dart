import 'dart:io';

import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('a fresh database migrates to the latest version', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    expect(db.userVersion, latestSchemaVersion);
    expect(
      db.select("SELECT name FROM sqlite_master WHERE name = 'work_intervals'"),
      hasLength(1),
    );
  });

  test('migrating twice is a no-op', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    migrate(db);
    expect(db.userVersion, latestSchemaVersion);
  });

  test('only pending steps run, in order', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final ran = <int>[];
    Migration step(int v) => Migration(v, (_) => ran.add(v));
    migrate(db, steps: [step(1)]);
    migrate(db, steps: [step(1), step(2), step(3)]);
    expect(ran, [1, 2, 3]);
    expect(db.userVersion, 3);
  });

  test('a failing step rolls back and keeps the last good version', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final steps = [
      Migration(1, (db) => db.execute('CREATE TABLE a (x);')),
      Migration(2, (db) {
        db.execute('CREATE TABLE b (x);');
        throw StateError('boom');
      }),
    ];
    expect(() => migrate(db, steps: steps), throwsStateError);
    expect(db.userVersion, 1);
    expect(
      db.select("SELECT name FROM sqlite_master WHERE name = 'b'"),
      isEmpty,
    );
  });

  test('a file from a newer build is refused', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.userVersion = latestSchemaVersion + 1;
    expect(() => migrate(db), throwsA(isA<SchemaTooNewException>()));
  });

  test('gaps in migration versions are rejected', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    expect(
      () => migrate(db, steps: [Migration(1, (_) {}), Migration(3, (_) {})]),
      throwsStateError,
    );
  });

  test('a file on disk reopens at the latest version', () {
    final dir = Directory.systemTemp.createTempSync('anisched');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.db';
    openAppDatabase(path).close();
    final db = openAppDatabase(path);
    addTearDown(db.close);
    expect(db.userVersion, latestSchemaVersion);
  });

  test('a v1 file upgrades to the latest and keeps its timer rows', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    migrate(db, steps: migrations.sublist(0, 1));
    db.execute('INSERT INTO work_intervals (started_at) VALUES (42);');
    migrate(db);
    expect(db.userVersion, latestSchemaVersion);
    expect(db.select('SELECT started_at FROM work_intervals'), hasLength(1));
    expect(
      db.select("SELECT name FROM sqlite_master WHERE name = 'tasks'"),
      hasLength(1),
    );
  });

  test('the app database opens with foreign keys on', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    expect(db.select('PRAGMA foreign_keys;').first.values.first, 1);
  });

  test('v14: old submitted and old done (checked OK) are both submitted', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    migrate(db, steps: migrations.where((m) => m.version <= 13).toList());
    db
      ..execute(
        "INSERT INTO works (title, currency, created_at) VALUES ('W', 'JPY', 0)",
      )
      ..execute(
        "INSERT INTO work_stages (work_id, name, position) VALUES (1, 'LO', 0)",
      )
      ..execute(
        "INSERT INTO episodes (work_id, number, sort_key) VALUES (1, '#1', '1')",
      )
      ..execute(
        "INSERT INTO cuts (episode_id, number, sort_key) VALUES (1, 'C1', 'c1'), (1, 'C2', 'c2'), (1, 'C3', 'c3')",
      )
      ..execute('''
INSERT INTO tasks (stage_id, cut_id, status, submitted_at, done_at)
        VALUES (1, 1, 'submitted', 100, NULL), (1, 2, 'done', 100, 200),
               (1, 3, 'in_progress', NULL, NULL)''');
    migrate(db);
    expect(
      db
          .select('SELECT status, submitted_at, done_at FROM tasks ORDER BY id')
          .map((r) => (r['status'], r['submitted_at'], r['done_at'])),
      [
        ('submitted', 100, 100),
        ('submitted', 100, 100),
        ('in_progress', null, null),
      ],
    );
    final preset = db
        .select(
          'SELECT i.name FROM stage_preset_items i JOIN stage_presets p '
          "ON p.id = i.preset_id WHERE p.name = '기본' ORDER BY i.position",
        )
        .map((r) => r['name']);
    expect(preset.skip(preset.length - 4), ['동화', '시아게', '리테이크', '캐릭터디자인']);
  });
}
