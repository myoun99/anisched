import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/document.dart';
import 'document_rows.dart';
import 'schema.dart';
import 'undo_history.dart';

export 'document_rows.dart' show NotADocumentException;

/// Size and content hash of a written document file.
typedef DocumentContent = ({int size, int hash});

/// Writes the database at [databasePath] as one self-contained document
/// file at [outPath], off the main isolate.
///
/// `VACUUM INTO` reads a consistent snapshot through its own read-only
/// connection, so the writer keeps going. The result is a rollback-journal
/// file (no `-wal`/`-shm` siblings needed to read it) stamped with
/// [documentApplicationId].
Future<DocumentContent> exportDocument(String databasePath, String outPath) =>
    Isolate.run(() => exportDocumentSync(databasePath, outPath));

/// [exportDocument] on the calling isolate.
DocumentContent exportDocumentSync(String databasePath, String outPath) {
  final out = File(outPath);
  if (out.existsSync()) out.deleteSync();
  final source = sqlite3.open(databasePath, mode: OpenMode.readOnly);
  try {
    source.execute('VACUUM INTO ?', [outPath]);
  } finally {
    source.close();
  }
  final doc = sqlite3.open(outPath);
  try {
    doc
      ..execute('PRAGMA journal_mode = DELETE')
      ..execute('PRAGMA application_id = $documentApplicationId');
  } finally {
    doc.close();
  }
  return (size: out.lengthSync(), hash: hashFileSync(outPath));
}

/// FNV-1a 64 over the file's bytes, read in chunks.
int hashFileSync(String path) {
  final file = File(path).openSync();
  try {
    var hash = fnv1a64Seed;
    while (true) {
      final chunk = file.readSync(1 << 16);
      if (chunk.isEmpty) return hash;
      hash = fnv1a64(chunk, hash);
    }
  } finally {
    file.closeSync();
  }
}

/// [hashFileSync] off the main isolate.
Future<int> hashFile(String path) => Isolate.run(() => hashFileSync(path));

/// Checks that [path] (a copy in the app container — it is modified) is an
/// Anisched document and migrates it to the latest schema, off the main
/// isolate. Throws [NotADocumentException] or [SchemaTooNewException].
Future<void> prepareImport(String path) =>
    Isolate.run(() => prepareImportSync(path));

/// [prepareImport] on the calling isolate.
void prepareImportSync(String path) {
  final Database db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readWrite);
  } on SqliteException catch (e) {
    throw NotADocumentException(path, e.message);
  }
  try {
    checkAndMigrateDocument(db, path);
  } finally {
    db.close();
  }
}

/// Replaces every row of [writer]'s database with the rows of the prepared
/// document at [path] ([prepareImport]), in one transaction.
///
/// The working file is never swapped: connections (the background reader)
/// stay valid and simply see the new rows. Deletes carry a WHERE so SQLite
/// reports each row to update hooks (the reader's staleness guard). Not a
/// step of the undo history, which it empties.
void importDocumentInto(CommonDatabase writer, String path) =>
    withoutHistory(writer, () => _importDocumentInto(writer, path));

void _importDocumentInto(CommonDatabase writer, String path) {
  writer.execute('ATTACH DATABASE ? AS doc', [path]);
  try {
    final mine = _tables(writer, 'main');
    final theirs = _tables(writer, 'doc');
    if (mine.length != theirs.length || !mine.every(theirs.contains)) {
      throw NotADocumentException(path, 'tables differ after migration');
    }
    writer.execute('BEGIN IMMEDIATE');
    try {
      writer.execute('PRAGMA defer_foreign_keys = ON');
      for (final t in mine) {
        writer.execute('DELETE FROM main."$t" WHERE 1');
      }
      for (final t in mine) {
        final cols = writer
            .select('SELECT name FROM pragma_table_info(?, ?)', [t, 'main'])
            .map((r) => '"${r.columnAt(0)}"')
            .join(', ');
        writer.execute(
          'INSERT INTO main."$t" ($cols) SELECT $cols FROM doc."$t"',
        );
      }
      writer.execute('COMMIT');
    } catch (_) {
      writer.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    writer.execute('DETACH DATABASE doc');
  }
}

List<String> _tables(CommonDatabase db, String schema) => [
  for (final r in db.select(
    "SELECT name FROM $schema.sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    r.columnAt(0) as String,
];

/// A fresh, empty document (latest schema, seeded presets and roles) at
/// [path] — what "new" imports.
void createEmptyDocumentSync(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  final db = sqlite3.open(path)
    ..execute('PRAGMA journal_mode = DELETE')
    ..execute('PRAGMA application_id = $documentApplicationId');
  try {
    migrate(db);
  } finally {
    db.close();
  }
}
