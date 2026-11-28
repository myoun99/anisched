import 'package:sqlite3/common.dart';

import '../models/document.dart';
import 'schema.dart';
import 'undo_history.dart';

/// The file is not an Anisched document (not SQLite, damaged, or another
/// app's database).
class NotADocumentException implements Exception {
  NotADocumentException(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'NotADocumentException($path: $reason)';
}

/// Checks that [db] (a copy — it is modified) is an Anisched document and
/// migrates it to the latest schema. [label] names it in errors. Throws
/// [NotADocumentException] or [SchemaTooNewException].
void checkAndMigrateDocument(CommonDatabase db, String label) {
  final int appId;
  final String check;
  try {
    appId = db.select('PRAGMA application_id').first.columnAt(0) as int;
    check = db.select('PRAGMA quick_check').first.columnAt(0) as String;
  } on SqliteException catch (e) {
    throw NotADocumentException(label, e.message);
  }
  if (appId != documentApplicationId) {
    throw NotADocumentException(label, 'not an Anisched document');
  }
  if (check != 'ok') throw NotADocumentException(label, check);
  db.execute('PRAGMA journal_mode = DELETE');
  migrate(db);
}

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
    throw NotADocumentException('', 'tables differ after migration');
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
