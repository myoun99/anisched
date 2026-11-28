import 'package:sqlite3/common.dart';

import '../models/document.dart';
import 'schema.dart';
import 'undo_history.dart';

/// Why a file is not an Anisched document (유저 2026-11-28 bug report:
/// the screen showed only the English message).
enum NotADocumentKind {
  /// No bytes — a cloud file not downloaded yet, or an empty pick.
  empty,

  /// Not a SQLite file (wrong header, or cut short before one).
  notSqlite,

  /// A SQLite database of another app.
  foreignApp,

  /// SQLite, ours, but damaged (the integrity check failed).
  damaged,

  /// Its tables differ from this version's after the update.
  tablesDiffer,

  /// Updating it to this version's schema failed.
  migrateFailed,
}

/// The file is not an Anisched document (empty, not SQLite, damaged,
/// another app's database, or it could not be brought up to date) —
/// [kind] says which, and what was seen is kept for diagnosis.
class NotADocumentException implements Exception {
  NotADocumentException(
    this.path,
    this.reason, {
    this.kind = NotADocumentKind.notSqlite,
    this.size,
    this.head,
    this.applicationId,
    this.userVersion,
    this.check,
  });

  final String path;
  final String reason;
  final NotADocumentKind kind;

  /// File size in bytes, when known.
  final int? size;

  /// The first bytes (up to 16), when read: `SQLite format 3\0` for any
  /// SQLite file.
  final List<int>? head;
  final int? applicationId;
  final int? userVersion;

  /// The integrity check's answer (`ok` when fine).
  final String? check;

  @override
  String toString() => [
    'NotADocumentException(${kind.name}: $reason',
    if (size != null) 'size=$size',
    if (head != null) 'head=${_hex(head!)}',
    if (applicationId != null) 'application_id=$applicationId',
    if (userVersion != null) 'user_version=$userVersion',
    if (check != null) 'check=$check',
    'path=$path)',
  ].join(', ');

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Every SQLite file starts with these 16 bytes.
const sqliteHeader = [
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
];

/// Checks a file's [size] and first bytes [head] before SQLite opens it:
/// throws [NotADocumentException] (`empty` or `notSqlite`) for an empty
/// file, one cut short before a whole header, or one that is not SQLite.
void checkDocumentHead(String label, int size, List<int> head) {
  final first = head.length > 16 ? head.sublist(0, 16) : head;
  if (size == 0) {
    throw NotADocumentException(
      label,
      'the file is empty',
      kind: NotADocumentKind.empty,
      size: 0,
    );
  }
  var sqlite = first.length == 16;
  for (var i = 0; sqlite && i < 16; i++) {
    if (first[i] != sqliteHeader[i]) sqlite = false;
  }
  if (!sqlite || size < 100) {
    throw NotADocumentException(
      label,
      'not a SQLite file',
      size: size,
      head: first,
    );
  }
}

/// Checks that [db] (a copy — it is modified) is an Anisched document and
/// migrates it to the latest schema. [label] names it in errors; [size]
/// and [head] go into them when known. Throws [NotADocumentException]
/// (with what was seen) or [SchemaTooNewException].
void checkAndMigrateDocument(
  CommonDatabase db,
  String label, {
  int? size,
  List<int>? head,
}) {
  final int appId;
  final int version;
  final String check;
  try {
    appId = db.select('PRAGMA application_id').first.columnAt(0) as int;
    version = db.select('PRAGMA user_version').first.columnAt(0) as int;
    check = db.select('PRAGMA quick_check').first.columnAt(0) as String;
  } on SqliteException catch (e) {
    throw NotADocumentException(
      label,
      e.message,
      kind: NotADocumentKind.damaged,
      size: size,
      head: head,
    );
  }
  NotADocumentException fail(String reason, NotADocumentKind kind) =>
      NotADocumentException(
        label,
        reason,
        kind: kind,
        size: size,
        head: head,
        applicationId: appId,
        userVersion: version,
        check: check,
      );
  if (appId != documentApplicationId) {
    throw fail(
      appId == 0 && version == 0 && _isBlank(db)
          ? 'an empty database'
          : 'not an Anisched document',
      appId == 0 && version == 0 && _isBlank(db)
          ? NotADocumentKind.empty
          : NotADocumentKind.foreignApp,
    );
  }
  if (check != 'ok') throw fail(check, NotADocumentKind.damaged);
  try {
    db.execute('PRAGMA journal_mode = DELETE');
    migrate(db);
  } on SqliteException catch (e) {
    throw fail(
      'update from v$version failed: ${e.message}',
      NotADocumentKind.migrateFailed,
    );
  }
}

bool _isBlank(CommonDatabase db) =>
    db
        .select("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'")
        .first
        .columnAt(0) ==
    0;

/// Replaces every row of [to] with the rows of [from] (both at the latest
/// schema), in one transaction on [to] — for two connections that cannot
/// ATTACH each other (the web build's IndexedDB and in-memory files).
/// Deletes carry a WHERE so update hooks see each row.
/// Not a step of [to]'s undo history, which it empties.
void copyAllRows(CommonDatabase from, CommonDatabase to) =>
    withoutHistory(to, () => _copyAllRows(from, to));

void _copyAllRows(CommonDatabase from, CommonDatabase to) {
  final mine = tableNames(to);
  final theirs = tableNames(from);
  if (mine.length != theirs.length || !mine.every(theirs.contains)) {
    throw NotADocumentException(
      '',
      'tables differ after migration',
      kind: NotADocumentKind.tablesDiffer,
    );
  }
  to.execute('BEGIN IMMEDIATE');
  try {
    to.execute('PRAGMA defer_foreign_keys = ON');
    for (final t in mine) {
      to.execute('DELETE FROM "$t" WHERE 1');
    }
    for (final t in mine) {
      final cols = [
        for (final r in to.select('SELECT name FROM pragma_table_info(?)', [t]))
          r.columnAt(0) as String,
      ];
      final list = cols.map((c) => '"$c"').join(', ');
      final insert = to.prepare(
        'INSERT INTO "$t" ($list) VALUES '
        '(${List.filled(cols.length, '?').join(', ')})',
      );
      try {
        for (final r in from.select('SELECT $list FROM "$t"')) {
          insert.execute(r.values);
        }
      } finally {
        insert.close();
      }
    }
    to.execute('COMMIT');
  } catch (_) {
    to.execute('ROLLBACK');
    rethrow;
  }
}

/// The user tables of [db]'s [schema], by name.
List<String> tableNames(CommonDatabase db, [String schema = 'main']) => [
  for (final r in db.select(
    "SELECT name FROM $schema.sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    r.columnAt(0) as String,
];
