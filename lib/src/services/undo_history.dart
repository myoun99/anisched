import 'dart:async';

import 'package:sqlite3/common.dart';

/// Undo and redo for every write to the document (유저 2026-11-28).
///
/// Triggers kept in the connection's temp schema write, for each row a
/// write touches, the SQL that puts the row back (sqlite.org, "Automatic
/// Undo/Redo Using SQLite"). Plain SQL, so it runs the same on the
/// device's SQLite and in the browser's WebAssembly one, where the session
/// extension is not built in. The log lives in `temp`: it is never part
/// of the document file, a save (`VACUUM INTO`) or the background
/// reader's connection.
///
/// One step is what one synchronous turn of the app writes — a `_write`
/// in the UI, a store call with its `holdPlaces` and every other write it
/// makes — closed at the next microtask. Undoing a step runs its log
/// backwards; the triggers record the way forward again, which becomes
/// the redo step. A new step empties the redo stack. At most [limit]
/// steps are kept.
///
/// Not recorded: the timer's target (`settings.timer_target` — a choice,
/// not an edit). A running timer writes nothing while it runs: only its
/// start, stop and edits are steps. Replacing the whole document (open,
/// new, a snapshot, a reload) is not a step and empties the history; see
/// [withoutHistory].
class UndoHistory {
  UndoHistory._(this.db, this.limit);

  /// Starts recording [db]'s writes; [of] finds it again.
  factory UndoHistory.attach(CommonDatabase db, {int limit = 200}) {
    final history = UndoHistory._(db, limit);
    _attached[db] = history;
    db.execute(
      'CREATE TEMP TABLE IF NOT EXISTS undo_log '
      '(seq INTEGER PRIMARY KEY AUTOINCREMENT, sql TEXT NOT NULL);',
    );
    history
      .._createTriggers()
      .._end = history._lastSeq()
      .._writes = db.updatesSync.listen(history._onUpdate);
    return history;
  }

  /// The history recording [db], if any.
  static UndoHistory? of(CommonDatabase db) => _attached[db];

  static final _attached = Expando<UndoHistory>('undo history');

  final CommonDatabase db;

  /// The most steps kept; the oldest go first.
  final int limit;

  final _undo = <_Step>[];
  final _redo = <_Step>[];
  final _changes = StreamController<void>.broadcast(sync: true);
  StreamSubscription<SqliteUpdate>? _writes;

  /// The last log row already in a step.
  int _end = 0;
  bool _closing = false;
  bool _replaying = false;
  bool _suspended = false;

  /// Fires when [canUndo] or [canRedo] may have changed, and after an
  /// [undo] or [redo] changed the rows (views read again).
  Stream<void> get changes => _changes.stream;

  bool get canUndo {
    _closeStep();
    return _undo.isNotEmpty;
  }

  bool get canRedo {
    _closeStep();
    return _redo.isNotEmpty;
  }

  /// Takes back the last step; false when there is none.
  bool undo() => _move(_undo, _redo);

  /// Does the last undone step again; false when there is none.
  bool redo() => _move(_redo, _undo);

  /// Forgets every step.
  void clear() {
    _closeStep();
    db.execute('DELETE FROM temp.undo_log;');
    _undo.clear();
    _redo.clear();
    _end = _lastSeq();
    _emit();
  }

  /// Stops recording.
  Future<void> detach() async {
    await _writes?.cancel();
    _dropTriggers();
    _attached[db] = null;
    await _changes.close();
  }

  bool _move(List<_Step> from, List<_Step> to) {
    _closeStep();
    if (from.isEmpty) return false;
    final step = from.removeLast();
    final before = _lastSeq();
    _replaying = true;
    db.execute('SAVEPOINT undo_replay;');
    try {
      // The steps between may pass through states the constraints only
      // accept at the end (a parent back after its child).
      db.execute('PRAGMA defer_foreign_keys = ON;');
      final sql = [
        for (final r in db.select(
          'SELECT sql FROM temp.undo_log WHERE seq BETWEEN ? AND ? '
          'ORDER BY seq DESC;',
          [step.first, step.last],
        ))
          r['sql'] as String,
      ];
      db.execute('DELETE FROM temp.undo_log WHERE seq BETWEEN ? AND ?;', [
        step.first,
        step.last,
      ]);
      sql.forEach(db.execute);
      db.execute('RELEASE undo_replay;');
    } catch (_) {
      db
        ..execute('ROLLBACK TO undo_replay;')
        ..execute('RELEASE undo_replay;');
      from.add(step);
      rethrow;
    } finally {
      _replaying = false;
    }
    final after = _lastSeq();
    if (after > before) to.add(_Step(before + 1, after));
    _end = after;
    _emit();
    return true;
  }

  void _onUpdate(SqliteUpdate u) {
    if (_closing || _replaying || u.tableName != 'undo_log') return;
    _closing = true;
    scheduleMicrotask(_closeStep);
  }

  /// Makes what was logged since the last step into a new step.
  void _closeStep() {
    if (!_closing) return;
    _closing = false;
    final last = _lastSeq();
    if (last <= _end) return;
    _undo.add(_Step(_end + 1, last));
    _end = last;
    for (final s in _redo) {
      _forget(s);
    }
    _redo.clear();
    while (_undo.length > limit) {
      _forget(_undo.removeAt(0));
    }
    _emit();
  }

  void _forget(_Step s) => db.execute(
    'DELETE FROM temp.undo_log WHERE seq BETWEEN ? AND ?;',
    [s.first, s.last],
  );

  /// The highest log row ever written (AUTOINCREMENT: never reused).
  int _lastSeq() =>
      db
              .select(
                "SELECT seq FROM temp.sqlite_sequence WHERE name = 'undo_log';",
              )
              .firstOrNull?['seq']
          as int? ??
      0;

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  T _withoutRecording<T>(T Function() body) {
    if (_suspended) return body();
    _closeStep();
    _suspended = true;
    _dropTriggers();
    try {
      return body();
    } finally {
      _createTriggers();
      _suspended = false;
      clear();
    }
  }

  void _createTriggers() {
    for (final table in _tables()) {
      final cols = [
        for (final r in db.select(
          "SELECT name FROM pragma_table_info(?, 'main');",
          [table],
        ))
          '"${r['name']}"',
      ];
      final on = 'main."$table"';
      // Literal SQL text inside the trigger's own string literal.
      final target = on.replaceAll("'", "''");
      String values(String row) =>
          cols.map((c) => 'quote($row.$c)').join(" || ',' || ");
      final skipNew = _skip[table]?.call('new') ?? '1';
      final skipOld = _skip[table]?.call('old') ?? '1';
      final changed = [
        for (final c in cols) 'old.$c IS NOT new.$c',
        'old.rowid IS NOT new.rowid',
      ].join(' OR ');
      db
        ..execute('''
CREATE TEMP TRIGGER "undo_i_$table" AFTER INSERT ON $on WHEN $skipNew
BEGIN INSERT INTO undo_log (sql)
  VALUES ('DELETE FROM $target WHERE rowid = ' || new.rowid); END;''')
        ..execute('''
CREATE TEMP TRIGGER "undo_d_$table" AFTER DELETE ON $on WHEN $skipOld
BEGIN INSERT INTO undo_log (sql)
  VALUES ('INSERT INTO $target (rowid, ${cols.join(', ').replaceAll("'", "''")}) VALUES ('
          || old.rowid || ',' || ${values('old')} || ')'); END;''')
        ..execute('''
CREATE TEMP TRIGGER "undo_u_$table" AFTER UPDATE ON $on
WHEN ($changed) AND $skipOld AND $skipNew
BEGIN INSERT INTO undo_log (sql)
  VALUES ('UPDATE $target SET rowid = ' || old.rowid
          ${cols.map((c) => "|| ', ${c.replaceAll("'", "''")} = ' || quote(old.$c)").join(' ')}
          || ' WHERE rowid = ' || new.rowid); END;''');
    }
  }

  void _dropTriggers() {
    for (final r in db.select(
      "SELECT name FROM temp.sqlite_master WHERE type = 'trigger' "
      "AND name LIKE 'undo\\_%' ESCAPE '\\';",
    )) {
      db.execute('DROP TRIGGER temp."${r['name']}";');
    }
  }

  List<String> _tables() => [
    for (final r in db.select(
      "SELECT name FROM main.sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name;",
    ))
      r['name'] as String,
  ];

  /// Rows left out of the history, as a condition on the row (`new` or
  /// `old`) that keeps the rest.
  static final _skip = <String, String Function(String row)>{
    'settings': (row) => "$row.key <> 'timer_target'",
  };
}

/// A run of log rows that undo (or redo) together.
class _Step {
  const _Step(this.first, this.last);
  final int first;
  final int last;
}

/// Runs [body] — which replaces [db]'s rows wholesale: opening a document,
/// a new one, a snapshot, a reload — without recording it, then empties
/// the history: there is nothing to undo back into.
T withoutHistory<T>(CommonDatabase db, T Function() body) {
  final history = UndoHistory.of(db);
  return history == null ? body() : history._withoutRecording(body);
}
