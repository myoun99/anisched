import 'dart:io';

import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_codec.dart';
import 'package:anisched/src/services/schema.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opening a document an older app wrote (유저 2026-11-28 bug: a v18 file
/// from the tablet would not open in the v20 app), and what a file that
/// is not a document says about itself.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('anisched-upgrade'));
  tearDown(() => dir.deleteSync(recursive: true));

  int ms(int day, [int hour = 10]) =>
      DateTime(2026, 11, day, hour).millisecondsSinceEpoch;

  /// A v18 document with what a user would have made: shared cuts, a cut
  /// handed off, archived ones, retakes, deadline revisions, holds, plans,
  /// timer stretches, rates, events of an episode, global and days off,
  /// lane pins and order — and numbers typed with a C under a # style,
  /// one of them clashing with a live value.
  String v18Document() {
    final path = '${dir.path}/tablet.anisched';
    final db = sqlite3.open(path);
    migrate(db, steps: migrations.where((m) => m.version <= 18).toList());
    db.execute('PRAGMA application_id = $documentApplicationId');
    for (final sql in [
      "INSERT INTO settings (key, value) VALUES ('cut_style', "
          '\'{"prefix":"#","digits":3}\'), (\'timer_target\', \'3\')',
      "INSERT INTO clients VALUES (1, '회사', 25, NULL, 4278255360)",
      "INSERT INTO works VALUES (1, 1, '작품', 'JPY', 0, NULL, 'up', 'fixed')",
      "INSERT INTO work_stages VALUES (1, 1, 'LO', 0, NULL), "
          "(2, 1, '원화', 1, NULL)",
      "INSERT INTO episodes VALUES (1, 1, '1', '', NULL, NULL), "
          "(2, 1, '#02', '', NULL, NULL)",
      "INSERT INTO parts VALUES (1, 1, 'A', 'a', 6, NULL, NULL)",
      '''
INSERT INTO cuts (id, episode_id, number, sort_key, length_ms, part_id,
                  shared_with, archived_at) VALUES
  (1, 1, '12', '', 3000, 1, NULL, NULL),
  (2, 1, 'C012', '', 3000, 1, NULL, NULL),
  (3, 1, 'C013', '', 3000, 1, NULL, 5),
  (4, 1, '13', '', 3000, 1, NULL, NULL),
  (5, 1, ' c14 ', '', 3000, 1, NULL, NULL),
  (6, 1, '15', '', 3000, 1, 5, NULL)''',
      "INSERT INTO storyboards VALUES (1, 1, '콘티', NULL)",
      "INSERT INTO episode_rates VALUES (1, 1, 'fixed', 3000)",
      '''
INSERT INTO tasks (id, stage_id, cut_id, storyboard_id, status, received_at,
                   submitted_at, done_at, archived_at, handed_off_at,
                   wait_state)
VALUES
  (1, 1, 1, NULL, 'submitted', ${ms(1)}, ${ms(5)}, ${ms(5)}, NULL, NULL, NULL),
  (2, 1, 2, NULL, 'received', ${ms(1)}, NULL, NULL, NULL, NULL, 1),
  (3, 1, 4, NULL, 'retake', ${ms(1)}, ${ms(6)}, ${ms(6)}, NULL, NULL, NULL),
  (4, 1, 5, NULL, 'done', ${ms(1)}, NULL, ${ms(7)}, NULL, NULL, NULL),
  (5, 1, 6, NULL, 'done', ${ms(1)}, NULL, ${ms(7)}, NULL, NULL, NULL),
  (6, 2, 1, NULL, 'received', ${ms(1)}, NULL, NULL, NULL, ${ms(8)}, NULL),
  (7, 1, 3, NULL, 'received', ${ms(1)}, NULL, NULL, ${ms(9)}, NULL, NULL),
  (8, 1, NULL, 1, 'in_progress', ${ms(1)}, NULL, NULL, NULL, NULL, NULL)''',
      'INSERT INTO retakes (task_id, take, received_at, paid, amount) '
          'VALUES (3, 2, ${ms(7)}, 1, 1500)',
      'INSERT INTO work_intervals (started_at, stopped_at, task_id) VALUES '
          '(${ms(2)}, ${ms(2, 12)}, 1), (${ms(3)}, ${ms(3, 11)}, 8)',
      'INSERT INTO part_stage_dues VALUES (1, 1, ${ms(30)})',
      'INSERT INTO part_stage_plans VALUES (1, 1, ${ms(20)}, ${ms(28)})',
      'INSERT INTO part_stage_kickoffs VALUES (1, 1, ${ms(1)})',
      "INSERT INTO part_stage_waits VALUES (1, 2, 'BG', NULL, ${ms(4)})",
      'INSERT INTO due_revisions (part_id, stage_id, task_id, revision, '
          'due_at, created_at) VALUES (1, 1, NULL, 1, ${ms(25)}, ${ms(1)}), '
          '(1, 1, NULL, 2, ${ms(30)}, ${ms(10)}), '
          '(NULL, NULL, 3, 1, ${ms(26)}, ${ms(1)})',
      '''
INSERT INTO events (episode_id, day, time_min, title, note, rest) VALUES
  (1, '2026-12-01', NULL, '아후레코', NULL, 0),
  (NULL, '2026-12-05', 600, '회의', '메모', 0),
  (NULL, '2026-12-29', NULL, '', NULL, 1)''',
      "INSERT INTO lane_pins VALUES ('part:1:1', 1)",
      "INSERT INTO group_order VALUES ('part:1:1', 0)",
    ]) {
      db.execute(sql);
    }
    db.close();
    return path;
  }

  test('a v18 document full of a user\'s work opens in this version', () {
    final doc = v18Document();
    final writer = openAppDatabase('${dir.path}/working.db');
    addTearDown(writer.close);
    final store = CatalogueStore(writer, clock: () => DateTime(2026, 11, 28));
    store.createWork('지금 있던 것');
    final history = UndoHistory.attach(writer);
    addTearDown(history.detach);

    prepareImportSync(doc);
    importDocumentInto(writer, doc);

    expect(writer.userVersion, latestSchemaVersion);
    expect(writer.select('PRAGMA foreign_key_check;'), isEmpty);
    expect(store.works().single.title, '작품');
    // Numbers became values; the clash kept both names and was recorded.
    expect(
      writer
          .select('SELECT number FROM cuts ORDER BY id')
          .map((r) => r['number']),
      ['12', 'C012', 'C013', '13', '14', '15'],
    );
    expect(store.settings.numberClashes.map((c) => c.number), ['C012']);
    expect(store.episodes(1).map((e) => e.number), ['#01', '#02']);
    // Everything reads.
    expect(store.partGroups(includeHandedOff: true), isNotEmpty);
    expect(store.today().entries, isNotEmpty);
    store
      ..signals()
      ..calendarLayout()
      ..stats(from: DateTime(2026, 11), to: DateTime(2026, 12))
      ..statsTree(from: DateTime(2026, 11), to: DateTime(2026, 12));
    final events = store.events(from: DateTime(2026, 12), to: DateTime(2027));
    expect(events[1]!.single.title, '아후레코');
    expect(events[null]!.map((e) => e.rest), [false, true]);
    expect(store.cardEvents(from: DateTime(2026), to: DateTime(2027)), isEmpty);
    expect(store.timerTarget(), 3);
    // Not a step to undo back from.
    expect(history.canUndo, isFalse);
  });

  group('a file that is not a document says what it is', () {
    NotADocumentException refusal(String path) {
      try {
        prepareImportSync(path);
      } on NotADocumentException catch (e) {
        return e;
      }
      fail('accepted $path');
    }

    test('empty (a cloud file not downloaded yet)', () {
      final path = '${dir.path}/empty.anisched';
      File(path).writeAsBytesSync(const []);
      final e = refusal(path);
      expect((e.kind, e.size), (NotADocumentKind.empty, 0));
    });

    test('cut short, or not SQLite at all', () {
      final whole = File(v18Document()).readAsBytesSync();
      final cut = '${dir.path}/cut.anisched';
      File(cut).writeAsBytesSync(whole.sublist(0, 10));
      final e = refusal(cut);
      expect(
        (e.kind, e.size, e.head!.length),
        (NotADocumentKind.notSqlite, 10, 10),
      );
      final text = '${dir.path}/note.anisched';
      File(text).writeAsStringSync('hello, this is not a database at all');
      expect(refusal(text).kind, NotADocumentKind.notSqlite);
      expect(refusal(text).toString(), contains('head=68656c6c6f'));
    });

    test('another app\'s database, a blank one, a damaged one', () {
      final other = '${dir.path}/other.db';
      sqlite3.open(other)
        ..execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)')
        ..close();
      final e = refusal(other);
      expect((e.kind, e.applicationId), (NotADocumentKind.foreignApp, 0));

      final blank = '${dir.path}/blank.db';
      sqlite3.open(blank)
        ..execute('PRAGMA user_version = 0')
        ..execute('CREATE TABLE t (x)')
        ..execute('DROP TABLE t')
        ..close();
      expect(refusal(blank).kind, NotADocumentKind.empty);

      final bytes = File(v18Document()).readAsBytesSync();
      for (var i = 4096; i < bytes.length; i++) {
        bytes[i] = 0x5a;
      }
      final broken = '${dir.path}/broken.anisched';
      File(broken).writeAsBytesSync(bytes);
      expect(refusal(broken).kind, NotADocumentKind.damaged);
    });
  });
}
