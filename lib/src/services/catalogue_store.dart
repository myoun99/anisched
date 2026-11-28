import 'package:sqlite3/common.dart';

import '../core/clock.dart';
import '../models/catalogue.dart';
import '../models/cut_numbers.dart';
import '../models/dashboard.dart';
import '../models/holidays.dart';
import '../models/lanes.dart';
import '../models/number_style.dart';
import '../models/progress.dart';
import '../models/stats.dart';
import '../models/work_interval.dart';
import 'settings_store.dart';

/// Writes to the work catalogue that carry a rule beyond a plain INSERT:
/// default stages, natural sort keys, retake numbering, rate resolution.
class CatalogueStore {
  CatalogueStore(this.db, {this.clock = systemClock})
    : settings = SettingsStore(db);

  final CommonDatabase db;

  final SettingsStore settings;

  /// Source of "now"; injectable for tests.
  final Clock clock;

  /// Creates a work whose editable stage list is a copy of [presetId]
  /// (the default preset when null). Later preset edits do not touch it.
  int createWork(
    String title, {
    String currency = 'JPY',
    int? clientId,
    int? presetId,
  }) => _transaction(() {
    db.execute(
      'INSERT INTO works (client_id, title, currency, created_at) '
      'VALUES (?, ?, ?, ?);',
      [clientId, title, currency, _now()],
    );
    final workId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO work_stages (work_id, name, position) '
      'SELECT ?, name, position FROM stage_preset_items '
      'WHERE preset_id = ? ORDER BY position;',
      [workId, presetId ?? defaultPresetId()],
    );
    return workId;
  });

  /// The id of the default stage preset.
  int defaultPresetId() =>
      db
              .select('SELECT id FROM stage_presets WHERE is_default = 1;')
              .first['id']
          as int;

  /// The preset's stage names in order.
  List<String> presetStages(int presetId) => [
    for (final r in db.select(
      'SELECT name FROM stage_preset_items WHERE preset_id = ? '
      'ORDER BY position, id;',
      [presetId],
    ))
      r['name'] as String,
  ];

  /// Replaces the preset's stages with [names], in order.
  void setPresetStages(int presetId, List<String> names) => _transaction(() {
    db.execute('DELETE FROM stage_preset_items WHERE preset_id = ?;', [
      presetId,
    ]);
    for (var i = 0; i < names.length; i++) {
      db.execute(
        'INSERT INTO stage_preset_items (preset_id, name, position) '
        'VALUES (?, ?, ?);',
        [presetId, names[i], i],
      );
    }
  });

  /// The work's live stages in order, as (id, name).
  List<({int id, String name})> stages(int workId) => [
    for (final r in db.select(
      'SELECT id, name FROM work_stages '
      'WHERE work_id = ? AND archived_at IS NULL ORDER BY position, id;',
      [workId],
    ))
      (id: r['id'] as int, name: r['name'] as String),
  ];

  // Cut and episode numbers are stored as values and shown in the
  // document's styles (models/number_style.dart): `C012A` is stored as
  // `12A` and reads `C012A` — or `0012A` once the style changes.

  /// The stored value of a cut number the user typed.
  String cutKey(String typed) => storedNumber(typed, settings.cutStyle);

  /// The stored value of an episode number the user typed.
  String episodeKey(String typed) => storedNumber(typed, settings.episodeStyle);

  int addEpisode(int workId, String number, {String? title}) {
    final v = episodeKey(number);
    db.execute(
      'INSERT INTO episodes (work_id, number, sort_key, title) '
      'VALUES (?, ?, ?, ?);',
      [workId, v, naturalSortKey(v), title],
    );
    return db.lastInsertRowId;
  }

  int addCut(int episodeId, String number, {int? lengthMs, int? partId}) {
    final v = cutKey(number);
    db.execute(
      'INSERT INTO cuts (episode_id, number, sort_key, length_ms, part_id) '
      'VALUES (?, ?, ?, ?, ?);',
      [episodeId, v, cutSortKey(v), lengthMs, partId],
    );
    return db.lastInsertRowId;
  }

  /// Adds many cuts to an episode in one transaction — for example the
  /// numbers from [parseCutNumbers]. Numbers already live in the episode
  /// (by value: `C012` and `12` are one) are skipped and reported as
  /// typed, not duplicated.
  ({List<int> added, List<String> skipped}) addCuts(
    int episodeId,
    Iterable<String> numbers, {
    int? partId,
    int? lengthMs,
  }) => _transaction(() {
    final existing = {
      for (final r in db.select(
        'SELECT number FROM cuts WHERE episode_id = ? AND archived_at IS NULL;',
        [episodeId],
      ))
        r['number'] as String,
    };
    final added = <int>[];
    final skipped = <String>[];
    final insert = db.prepare(
      'INSERT INTO cuts (episode_id, number, sort_key, length_ms, part_id) '
      'VALUES (?, ?, ?, ?, ?);',
    );
    final style = settings.cutStyle;
    try {
      for (final typed in numbers) {
        final n = storedNumber(typed, style);
        if (!existing.add(n)) {
          skipped.add(typed);
          continue;
        }
        insert.execute([episodeId, n, cutSortKey(n), lengthMs, partId]);
        added.add(db.lastInsertRowId);
      }
    } finally {
      insert.close();
    }
    return (added: added, skipped: skipped);
  });

  /// Adds an episode and its cuts from what the user typed (see
  /// [parseCutNumbers]), optionally in a new part, in one transaction.
  /// Unreadable input changes nothing and throws [CutNumbersException].
  ({int episodeId, int? partId, List<int> cutIds}) addEpisodeWithCuts(
    int workId,
    String episodeNumber,
    String cuts, {
    String? partLabel,
    int? lengthMs,
  }) {
    final parsed = parseCutNumbers(cuts);
    if (!parsed.ok) throw CutNumbersException(parsed.errors);
    return _transaction(() {
      final ep = addEpisode(workId, episodeNumber);
      final part = partLabel == null
          ? null
          : addPart(ep, partLabel, plannedCutCount: parsed.numbers.length);
      final added = addCuts(
        ep,
        parsed.numbers,
        partId: part,
        lengthMs: lengthMs,
      ).added;
      return (episodeId: ep, partId: part, cutIds: added);
    });
  }

  /// A work, its first episode and its cuts in one go — see [createWork]
  /// and [addEpisodeWithCuts].
  ({int workId, int episodeId, int? partId, List<int> cutIds})
  createWorkWithCuts(
    String title,
    String episodeNumber,
    String cuts, {
    String currency = 'JPY',
    int? clientId,
    int? presetId,
    String? partLabel,
  }) {
    final parsed = parseCutNumbers(cuts);
    if (!parsed.ok) throw CutNumbersException(parsed.errors);
    return _transaction(() {
      final w = createWork(
        title,
        currency: currency,
        clientId: clientId,
        presetId: presetId,
      );
      final r = addEpisodeWithCuts(
        w,
        episodeNumber,
        cuts,
        partLabel: partLabel,
      );
      return (
        workId: w,
        episodeId: r.episodeId,
        partId: r.partId,
        cutIds: r.cutIds,
      );
    });
  }

  /// Archives the given cuts (missing numbers picked on the grid); they
  /// can be restored.
  void removeCutIds(Iterable<int> cutIds) => _transaction(() {
    for (final id in cutIds) {
      archive(ArchiveKind.cut, id);
    }
  });

  /// Role presets in order, each with the stage names it takes on.
  List<({int id, String name, List<String> stages})> roles() {
    final stages = <int, List<String>>{};
    for (final r in db.select(
      'SELECT role_id, stage_name FROM role_stages ORDER BY role_id, position;',
    )) {
      (stages[r['role_id'] as int] ??= []).add(r['stage_name'] as String);
    }
    return [
      for (final r in db.select(
        'SELECT id, name FROM roles ORDER BY position, id;',
      ))
        (
          id: r['id'] as int,
          name: r['name'] as String,
          stages: stages[r['id'] as int] ?? const [],
        ),
    ];
  }

  /// Adds a role at the end and returns its id.
  int createRole(String name, List<String> stageNames) => _transaction(() {
    db.execute(
      'INSERT INTO roles (name, position) '
      'VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM roles));',
      [name],
    );
    final id = db.lastInsertRowId;
    setRoleStages(id, stageNames);
    return id;
  });

  void renameRole(int roleId, String name) =>
      db.execute('UPDATE roles SET name = ? WHERE id = ?;', [name, roleId]);

  /// Replaces a role's stage names, in order.
  void setRoleStages(int roleId, List<String> stageNames) => _transaction(() {
    db.execute('DELETE FROM role_stages WHERE role_id = ?;', [roleId]);
    final names = stageNames.toSet().toList();
    for (var i = 0; i < names.length; i++) {
      db.execute(
        'INSERT INTO role_stages (role_id, stage_name, position) '
        'VALUES (?, ?, ?);',
        [roleId, names[i], i],
      );
    }
  });

  void deleteRole(int roleId) => _transaction(() {
    db
      ..execute('DELETE FROM role_stages WHERE role_id = ?;', [roleId])
      ..execute('DELETE FROM roles WHERE id = ?;', [roleId]);
  });

  /// Registers work by stage — the checkboxes on the registration
  /// screen: each of [stageIds] gets a task on every cut of [partId], or
  /// on each of [cutIds] for cuts outside a part. Cut × stage pairs that
  /// already have a task are skipped. Returns the new task ids.
  List<int> addTasksForStages(
    List<int> stageIds, {
    int? partId,
    List<int> cutIds = const [],
  }) => _transaction(() {
    final created = <int>[];
    for (final stage in stageIds) {
      if (partId != null) created.addAll(addTasksForPart(partId, stage));
      for (final cut in cutIds) {
        final has = db.select(
          'SELECT 1 FROM tasks WHERE cut_id = ? AND stage_id = ? '
          'AND archived_at IS NULL;',
          [cut, stage],
        );
        if (has.isEmpty) created.add(addTask(stage, cutId: cut));
      }
    }
    return created;
  });

  /// The work's stage ids for a role — the shortcut that ticks the
  /// role's checkboxes. A stage name the work lacks is added at the end
  /// of its list.
  List<int> roleStageIds(int roleId, int workId) => _transaction(() {
    final names = [
      for (final r in db.select(
        'SELECT stage_name FROM role_stages WHERE role_id = ? ORDER BY position;',
        [roleId],
      ))
        r['stage_name'] as String,
    ];
    return [
      for (final name in names)
        stages(workId).where((s) => s.name == name).firstOrNull?.id ??
            addStage(workId, name),
    ];
  });

  /// Registers work by role: [roleStageIds] then [addTasksForStages].
  List<int> applyRole(
    int roleId, {
    required int workId,
    int? partId,
    List<int> cutIds = const [],
  }) => _transaction(
    () => addTasksForStages(
      roleStageIds(roleId, workId),
      partId: partId,
      cutIds: cutIds,
    ),
  );

  /// How cut and episode numbers are written (document settings,
  /// [SettingsStore.cutStyle] and [SettingsStore.episodeStyle]).
  ({NumberStyle cut, NumberStyle episode}) numberStyles() =>
      (cut: settings.cutStyle, episode: settings.episodeStyle);

  /// The cut number the user typed, in the cut style: 1 → `C001`.
  String cutNumberFor(int number) => formatCutNumber(number, settings.cutStyle);

  /// The episode number the user typed, in the episode style: 7 → `#07`.
  String episodeNumberFor(int number) =>
      formatEpisodeNumber(number, settings.episodeStyle);

  /// Adds [count] cuts from [start] up to an episode in the cut style
  /// (see [addCuts]).
  ({List<int> added, List<String> skipped}) addCutRun(
    int episodeId, {
    required int start,
    required int count,
    int? partId,
    int? lengthMs,
  }) {
    final f = settings.cutStyle;
    return addCuts(
      episodeId,
      cutNumberRun(
        start: start,
        count: count,
        prefix: f.prefix,
        width: f.digits,
      ),
      partId: partId,
      lengthMs: lengthMs,
    );
  }

  /// Takes missing numbers out of an episode (archives those cuts, so
  /// they can be restored). Returns the numbers that were not there.
  List<String> removeCuts(int episodeId, Iterable<String> numbers) =>
      _transaction(() {
        final missing = <String>[];
        for (final n in numbers) {
          db.execute(
            'UPDATE cuts SET archived_at = ? WHERE episode_id = ? '
            'AND number = ? AND archived_at IS NULL;',
            [_now(), episodeId, cutKey(n)],
          );
          if (db.updatedRows == 0) missing.add(n);
        }
        return missing;
      });

  /// Marks cuts of one episode as one shared cut (겸용). Every cut keeps
  /// its own row, length (per-second pay counts each) and tasks; the views
  /// label them together as `C012-014`. A cut already in another shared
  /// group leaves it. Returns the group's first cut (by number).
  int linkSharedCuts(List<int> cutIds) => _transaction(() {
    final ids = cutIds.toSet().toList();
    if (ids.length < 2) throw ArgumentError('A shared cut needs two cuts.');
    final rows = db.select(
      'SELECT id, episode_id FROM cuts WHERE id IN '
      '(${List.filled(ids.length, '?').join(', ')}) '
      'AND archived_at IS NULL ORDER BY sort_key, id;',
      ids,
    );
    if (rows.length != ids.length ||
        rows.map((r) => r['episode_id']).toSet().length != 1) {
      throw ArgumentError('Link live cuts of one episode only.');
    }
    for (final id in ids) {
      _leaveSharedGroup(id);
    }
    final head = rows.first['id'] as int;
    for (final r in rows.skip(1)) {
      db.execute('UPDATE cuts SET shared_with = ? WHERE id = ?;', [
        head,
        r['id'],
      ]);
    }
    return head;
  });

  /// Each live shared group's label (`C012-014`), by its first cut.
  Map<int, String> _sharedLabels() {
    final byGroup = <int, List<String>>{};
    for (final r in db.select('''
SELECT number, COALESCE(shared_with, id) AS g FROM cuts
WHERE archived_at IS NULL AND (shared_with IS NOT NULL
  OR id IN (SELECT shared_with FROM cuts WHERE shared_with IS NOT NULL))
ORDER BY sort_key, id;''')) {
      (byGroup[r['g'] as int] ??= []).add(r['number'] as String);
    }
    final style = settings.cutStyle;
    return {
      for (final e in byGroup.entries)
        if (e.value.length > 1)
          e.key: sharedCutNumber(
            shownNumber(e.value.first, style),
            shownNumber(e.value.last, style),
          ),
    };
  }

  /// Takes a cut out of its shared group; a group left with one cut
  /// dissolves.
  void unlinkSharedCut(int cutId) =>
      _transaction(() => _leaveSharedGroup(cutId));

  void _leaveSharedGroup(int cutId) {
    final head =
        db.select(
              'SELECT COALESCE(shared_with, id) AS h FROM cuts WHERE id = ?;',
              [cutId],
            ).first['h']
            as int;
    if (head == cutId) {
      // The first cut leaves: the next one leads the rest.
      final rest = [
        for (final r in db.select(
          'SELECT id FROM cuts WHERE shared_with = ? ORDER BY sort_key, id;',
          [cutId],
        ))
          r['id'] as int,
      ];
      if (rest.isEmpty) return;
      db
        ..execute('UPDATE cuts SET shared_with = NULL WHERE id = ?;', [
          rest.first,
        ])
        ..execute('UPDATE cuts SET shared_with = ? WHERE shared_with = ?;', [
          rest.first,
          cutId,
        ]);
    } else {
      db.execute('UPDATE cuts SET shared_with = NULL WHERE id = ?;', [cutId]);
    }
  }

  /// Renames cuts in one go — swaps included (`C1`↔`C2`). Fails, changing
  /// nothing, if a new number is already used by another live cut.
  void renumberCuts(Map<int, String> newNumbers) => _transaction(() {
    for (final id in newNumbers.keys) {
      db.execute('UPDATE cuts SET number = ? WHERE id = ?;', [
        '\$renumber\$$id',
        id,
      ]);
    }
    try {
      newNumbers.forEach(_rename);
    } on SqliteException {
      throw StateError('A new cut number is already in use.');
    }
  });

  void _rename(int cutId, String number) {
    final v = cutKey(number);
    db.execute('UPDATE cuts SET number = ?, sort_key = ? WHERE id = ?;', [
      v,
      cutSortKey(v),
      cutId,
    ]);
  }

  void renameClient(int clientId, String name) =>
      db.execute('UPDATE clients SET name = ? WHERE id = ?;', [name, clientId]);

  /// Sets a client's closing day; null closes at month end.
  void setClientClosingDay(int clientId, int? day) => db.execute(
    'UPDATE clients SET closing_day = ? WHERE id = ?;',
    [day, clientId],
  );

  void renameWork(int workId, String title) =>
      db.execute('UPDATE works SET title = ? WHERE id = ?;', [title, workId]);

  void setWorkClient(int workId, int? clientId) => db.execute(
    'UPDATE works SET client_id = ? WHERE id = ?;',
    [clientId, workId],
  );

  void setWorkCurrency(int workId, String currency) => db.execute(
    'UPDATE works SET currency = ? WHERE id = ?;',
    [currency, workId],
  );

  /// Renames an episode (its number keeps sorting naturally) and sets or
  /// clears its title.
  void renameEpisode(int episodeId, String number, {String? title}) {
    final v = episodeKey(number);
    db.execute(
      'UPDATE episodes SET number = ?, sort_key = ?, title = ? WHERE id = ?;',
      [v, naturalSortKey(v), title, episodeId],
    );
  }

  /// Puts cuts in a part (or takes them out with null). The part must be
  /// in the cuts' episode.
  void setCutsPart(Iterable<int> cutIds, int? partId) => _transaction(() {
    for (final id in cutIds) {
      db.execute(
        'UPDATE cuts SET part_id = ?1 WHERE id = ?2 AND (?1 IS NULL OR '
        'episode_id = (SELECT episode_id FROM parts WHERE id = ?1));',
        [partId, id],
      );
      if (db.updatedRows != 1) {
        throw ArgumentError('Cut $id is not in the part\'s episode.');
      }
    }
  });

  /// Sets or clears a cut's length (for per-second rates).
  void setCutLength(int cutId, int? lengthMs) => db.execute(
    'UPDATE cuts SET length_ms = ? WHERE id = ?;',
    [lengthMs, cutId],
  );

  void renamePart(int partId, String label) => db.execute(
    'UPDATE parts SET label = ?, sort_key = ? WHERE id = ?;',
    [label, naturalSortKey(label), partId],
  );

  /// Sets or clears how many cuts the part is expected to have.
  void setPlannedCutCount(int partId, int? count) => db.execute(
    'UPDATE parts SET planned_cut_count = ? WHERE id = ?;',
    [count, partId],
  );

  /// Removes the part's deadline for a stage, every revision; its cuts
  /// keep their own.
  void clearPartDue(int partId, int stageId) => _transaction(() {
    _holdBeforeDates();
    _deleteRevisions(DueTarget.part(partId, stageId));
    db.execute(
      'DELETE FROM part_stage_dues WHERE part_id = ? AND stage_id = ?;',
      [partId, stageId],
    );
  });

  // ---- deadline revisions (1st, 2nd …) ----

  (String, List<Object?>) _dueWhere(DueTarget target) => target.taskId != null
      ? ('task_id = ?', [target.taskId])
      : (
          'task_id IS NULL AND part_id = ? AND stage_id = ?',
          [target.partId, target.stageId],
        );

  /// Every revision of [target]'s deadline, first first.
  List<DueRevision> dueRevisions(DueTarget target) {
    final (where, args) = _dueWhere(target);
    return [
      for (final r in db.select(
        'SELECT revision, due_at, created_at FROM due_revisions '
        'WHERE $where ORDER BY revision;',
        args,
      ))
        (
          revision: r['revision'] as int,
          dueAt: _utc(r['due_at'] as int),
          createdAt: _utc(r['created_at'] as int),
        ),
    ];
  }

  /// A new revision of [target]'s deadline (the deadline was extended);
  /// it becomes the deadline in force. Answers its number.
  int extendDue(DueTarget target, DateTime dueAt) => _transaction(() {
    _holdBeforeDates();
    final (where, args) = _dueWhere(target);
    final next =
        db
                .select(
                  'SELECT COALESCE(MAX(revision), 0) + 1 AS n '
                  'FROM due_revisions WHERE $where;',
                  args,
                )
                .first['n']
            as int;
    db.execute(
      'INSERT INTO due_revisions (part_id, stage_id, task_id, revision, '
      'due_at, created_at) VALUES (?, ?, ?, ?, ?, ?);',
      [target.partId, target.stageId, target.taskId, next, _ms(dueAt), _now()],
    );
    _syncDue(target);
    return next;
  });

  /// Corrects revision [revision] (e.g. the 1st deadline itself). Throws
  /// [StateError] when there is no such revision.
  void editDueRevision(DueTarget target, int revision, DateTime dueAt) =>
      _transaction(() {
        _holdBeforeDates();
        final (where, args) = _dueWhere(target);
        db.execute(
          'UPDATE due_revisions SET due_at = ? WHERE $where AND revision = ?;',
          [_ms(dueAt), ...args, revision],
        );
        if (db.updatedRows == 0) {
          throw StateError('No revision $revision of this deadline.');
        }
        _syncDue(target);
      });

  /// Drops revision [revision]; later ones move down a number. Removing
  /// the only one removes the deadline.
  void removeDueRevision(DueTarget target, int revision) => _transaction(() {
    _holdBeforeDates();
    final (where, args) = _dueWhere(target);
    db.execute('DELETE FROM due_revisions WHERE $where AND revision = ?;', [
      ...args,
      revision,
    ]);
    if (db.updatedRows == 0) {
      throw StateError('No revision $revision of this deadline.');
    }
    final later = [
      for (final r in db.select(
        'SELECT revision FROM due_revisions WHERE $where AND revision > ? '
        'ORDER BY revision;',
        [...args, revision],
      ))
        r['revision'] as int,
    ];
    for (final n in later) {
      db.execute(
        'UPDATE due_revisions SET revision = ? WHERE $where AND revision = ?;',
        [n - 1, ...args, n],
      );
    }
    _syncDue(target);
  });

  /// Sets the deadline in force: corrects the last revision, or makes the
  /// first when there is none.
  void _setCurrentDue(DueTarget target, DateTime dueAt) {
    final (where, args) = _dueWhere(target);
    final last =
        db
                .select(
                  'SELECT MAX(revision) AS n FROM due_revisions WHERE $where;',
                  args,
                )
                .first['n']
            as int?;
    if (last == null) {
      extendDue(target, dueAt);
    } else {
      editDueRevision(target, last, dueAt);
    }
  }

  void _deleteRevisions(DueTarget target) {
    final (where, args) = _dueWhere(target);
    db.execute('DELETE FROM due_revisions WHERE $where;', args);
  }

  /// Copies the last revision into the current-deadline column readers use.
  void _syncDue(DueTarget target) {
    final (where, args) = _dueWhere(target);
    final rows = db.select(
      'SELECT due_at FROM due_revisions WHERE $where '
      'ORDER BY revision DESC LIMIT 1;',
      args,
    );
    final due = rows.isEmpty ? null : rows.first['due_at'] as int;
    if (target.taskId != null) {
      db.execute('UPDATE tasks SET due_at = ? WHERE id = ?;', [
        due,
        target.taskId,
      ]);
    } else if (due == null) {
      db.execute(
        'DELETE FROM part_stage_dues WHERE part_id = ? AND stage_id = ?;',
        [target.partId, target.stageId],
      );
    } else {
      db.execute(
        'INSERT INTO part_stage_dues (part_id, stage_id, due_at) '
        'VALUES (?, ?, ?) ON CONFLICT (part_id, stage_id) '
        'DO UPDATE SET due_at = excluded.due_at;',
        [target.partId, target.stageId, due],
      );
    }
  }

  // ---- waiting (대기) ----

  /// Puts a part × stage on hold ([waiting]) or takes it off; [reason]
  /// and [until] (expected) are optional. Cuts with their own setting keep
  /// it (see [setTaskWaiting], [followPartWaiting]).
  void setPartWaiting(
    int partId,
    int stageId, {
    required bool waiting,
    String? reason,
    DateTime? until,
  }) {
    if (!waiting) {
      db.execute(
        'DELETE FROM part_stage_waits WHERE part_id = ? AND stage_id = ?;',
        [partId, stageId],
      );
      return;
    }
    db.execute(
      'INSERT INTO part_stage_waits (part_id, stage_id, reason, until_at, '
      'since_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (part_id, stage_id) '
      'DO UPDATE SET reason = excluded.reason, until_at = excluded.until_at;',
      [partId, stageId, _blank(reason), _ms(until), _now()],
    );
  }

  /// One task's own waiting setting, overriding its part × stage.
  void setTaskWaiting(
    int taskId, {
    required bool waiting,
    String? reason,
    DateTime? until,
  }) =>
      setWaitingMany([taskId], waiting: waiting, reason: reason, until: until);

  /// [setTaskWaiting] for many tasks in one transaction.
  void setWaitingMany(
    Iterable<int> taskIds, {
    required bool waiting,
    String? reason,
    DateTime? until,
  }) => _transaction(() {
    final now = _now();
    final stmt = db.prepare(
      'UPDATE tasks SET wait_state = ?, wait_reason = ?, wait_until = ?, '
      'wait_since = CASE WHEN ? = 1 THEN COALESCE(wait_since, ?) END '
      'WHERE id = ?;',
    );
    try {
      for (final id in taskIds) {
        final state = waiting ? 1 : 0;
        final why = waiting ? _blank(reason) : null;
        final expected = waiting ? _ms(until) : null;
        stmt.execute([state, why, expected, state, now, id]);
      }
    } finally {
      stmt.close();
    }
  });

  /// Drops the tasks' own waiting setting: they follow their part × stage.
  void followPartWaiting(Iterable<int> taskIds) => _transaction(() {
    for (final id in taskIds) {
      db.execute(
        'UPDATE tasks SET wait_state = NULL, wait_reason = NULL, '
        'wait_until = NULL, wait_since = NULL WHERE id = ?;',
        [id],
      );
    }
  });

  /// Open cuts in hand and on hold, over every live unit — the 「보유」
  /// figure and what waits beside it.
  ({int inHand, int waiting}) holding() {
    var inHand = 0;
    var waiting = 0;
    for (final t in taskRows()) {
      if (!t.status.isOpen) continue;
      if (t.waiting) {
        waiting++;
      } else {
        inHand++;
      }
    }
    return (inHand: inHand, waiting: waiting);
  }

  // ---- handed off (빠짐) ----

  /// Takes [taskIds] off the user's hands — someone else does them now.
  /// They leave the lists, the cuts in hand, the pace and the calendar;
  /// their timer time stays in the statistics. [note] is optional.
  void handOff(Iterable<int> taskIds, {String? note}) => _transaction(() {
    final now = _now();
    for (final id in taskIds) {
      db.execute(
        'UPDATE tasks SET handed_off_at = COALESCE(handed_off_at, ?), '
        'handed_off_note = ? WHERE id = ?;',
        [now, _blank(note), id],
      );
    }
  });

  /// [handOff] for every live task of a part × stage. Answers their ids.
  List<int> handOffPart(int partId, int stageId, {String? note}) =>
      _transaction(() {
        final ids = [
          for (final r in db.select(
            'SELECT t.id FROM live_tasks t JOIN cuts c ON c.id = t.cut_id '
            'WHERE c.part_id = ? AND t.stage_id = ?;',
            [partId, stageId],
          ))
            r['id'] as int,
        ];
        handOff(ids, note: note);
        return ids;
      });

  /// Brings handed-off tasks back.
  void undoHandOff(Iterable<int> taskIds) => _transaction(() {
    for (final id in taskIds) {
      db.execute(
        'UPDATE tasks SET handed_off_at = NULL, handed_off_note = NULL '
        'WHERE id = ?;',
        [id],
      );
    }
  });

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  static DateTime _utc(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  static DateTime? _utcOrNull(Object? ms) =>
      ms == null ? null : _utc(ms as int);

  /// Adds a client; [closingDay] null closes at month end.
  int addClient(String name, {int? closingDay, int? color}) {
    db.execute(
      'INSERT INTO clients (name, closing_day, color) VALUES (?, ?, ?);',
      [name, closingDay, color],
    );
    return db.lastInsertRowId;
  }

  /// Sets a client's colour (ARGB); null goes back to the default grey.
  void setClientColor(int clientId, int? color) => db.execute(
    'UPDATE clients SET color = ? WHERE id = ?;',
    [color, clientId],
  );

  List<ClientRow> clients() => [
    for (final r in db.select(
      'SELECT id, name, closing_day, color, '
      '${_inUseSql(CatalogueKind.client, 'clients.id')} AS used FROM clients '
      'WHERE archived_at IS NULL '
      'ORDER BY name, id;',
    ))
      _clientRow(r),
  ];

  static ClientRow _clientRow(Row r, {String inUse = 'used'}) => (
    id: r['id'] as int,
    name: r['name'] as String,
    closingDay: r['closing_day'] as int?,
    color: r['color'] as int?,
    inUse: r[inUse] == 1,
  );

  /// Clients whose name contains [query] (any case; empty = all), most
  /// recently used first — by the latest activity on their works.
  List<ClientRow> searchClients(String query, {int limit = 50}) => [
    for (final r in db.select(
      '''
SELECT cl.id, cl.name, cl.closing_day, cl.color,
  (SELECT MAX(COALESCE(
     (SELECT MAX(MAX(COALESCE(t.submitted_at, 0), COALESCE(t.received_at, 0)))
      FROM work_stages s JOIN tasks t ON t.stage_id = s.id
      WHERE s.work_id = w.id), w.created_at))
   FROM works w WHERE w.client_id = cl.id AND w.archived_at IS NULL) AS used,
  ${_inUseSql(CatalogueKind.client, 'cl.id')} AS in_use
FROM clients cl
WHERE cl.archived_at IS NULL AND cl.name LIKE ? ESCAPE '\\'
ORDER BY used IS NULL, used DESC, cl.name, cl.id
LIMIT ?;''',
      [_like(query), limit],
    ))
      _clientRow(r, inUse: 'in_use'),
  ];

  /// Live works whose title contains [query] (any case; empty = all),
  /// optionally of one client, most recently used first — by the latest
  /// task activity, else when the work was made.
  List<WorkRow> searchWorks(String query, {int? clientId, int limit = 50}) => [
    for (final r in db.select(
      '''
SELECT w.id, w.title, w.currency, w.client_id,
  COALESCE((SELECT MAX(MAX(COALESCE(t.submitted_at, 0),
                           COALESCE(t.received_at, 0)))
            FROM work_stages s JOIN tasks t ON t.stage_id = s.id
            WHERE s.work_id = w.id), w.created_at) AS used,
  ${_inUseSql(CatalogueKind.work, 'w.id')} AS in_use
FROM works w
WHERE w.archived_at IS NULL AND w.title LIKE ? ESCAPE '\\'
  AND (? IS NULL OR w.client_id = ?)
ORDER BY used DESC, w.id DESC
LIMIT ?;''',
      [_like(query), clientId, clientId, limit],
    ))
      _workRow(r),
  ];

  static WorkRow _workRow(Row r) => (
    id: r['id'] as int,
    title: r['title'] as String,
    currency: r['currency'] as String,
    clientId: r['client_id'] as int?,
    inUse: r['in_use'] == 1,
  );

  /// A work's episodes whose number or title contains [query], in number
  /// order.
  List<EpisodeRow> searchEpisodes(int workId, String query) {
    final q = query.trim().toLowerCase();
    return [
      for (final e in episodes(workId))
        if (e.number.toLowerCase().contains(q) ||
            (e.title ?? '').toLowerCase().contains(q))
          e,
    ];
  }

  /// A LIKE pattern matching [query] anywhere, with `%`, `_` and `\`
  /// taken literally.
  static String _like(String query) =>
      '%${query.trim().replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%';

  /// Live works, newest first.
  List<WorkRow> works() => [
    for (final r in db.select(
      'SELECT id, title, currency, client_id, '
      '${_inUseSql(CatalogueKind.work, 'works.id')} AS in_use FROM works '
      'WHERE archived_at IS NULL ORDER BY created_at DESC, id DESC;',
    ))
      _workRow(r),
  ];

  /// A work's live episodes in number order, numbers in the episode style.
  List<EpisodeRow> episodes(int workId) {
    final style = settings.episodeStyle;
    return [
      for (final r in db.select(
        'SELECT id, number, title, '
        '${_inUseSql(CatalogueKind.episode, 'episodes.id')} AS in_use '
        'FROM episodes '
        'WHERE work_id = ? AND archived_at IS NULL ORDER BY sort_key, id;',
        [workId],
      ))
        (
          id: r['id'] as int,
          number: shownNumber(r['number'] as String, style),
          title: r['title'] as String?,
          inUse: r['in_use'] == 1,
        ),
    ];
  }

  /// An episode's live parts in label order, with their live cut counts.
  List<PartRow> parts(int episodeId) => [
    for (final r in db.select(
      'SELECT p.id, p.label, p.planned_cut_count, '
      '(SELECT COUNT(*) FROM cuts c WHERE c.part_id = p.id '
      'AND c.archived_at IS NULL) AS cut_count, '
      '${_inUseSql(CatalogueKind.part, 'p.id')} AS in_use '
      'FROM parts p WHERE p.episode_id = ? AND p.archived_at IS NULL '
      'ORDER BY p.sort_key, p.id;',
      [episodeId],
    ))
      (
        id: r['id'] as int,
        label: r['label'] as String,
        plannedCutCount: r['planned_cut_count'] as int?,
        cutCount: r['cut_count'] as int,
        inUse: r['in_use'] == 1,
      ),
  ];

  // ---- events (유저 2026-11-28) ----

  /// Puts an event on [date] (its local day), at [timeMinutes] past
  /// midnight or all day (null), on [episodeId]'s rows or on none.
  ///
  /// With [card] (a `PartGroup.key`), the event belongs to that card only
  /// (its episode comes from the card; [episodeId] is not needed).
  int addEvent({
    int? episodeId,
    String? card,
    required DateTime date,
    int? timeMinutes,
    required String title,
    String? note,
    bool rest = false,
  }) {
    final place = _eventPlace(episodeId, card);
    _checkEvent(timeMinutes, place.episode, rest);
    db.execute(
      'INSERT INTO events (episode_id, part_id, stage_id, day, time_min, '
      'title, note, rest) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        place.episode,
        place.part,
        place.stage,
        _day(date),
        timeMinutes,
        title,
        note,
        if (rest) 1 else 0,
      ],
    );
    return db.lastInsertRowId;
  }

  /// Rewrites every field of event [id]. Its card stays unless [card]
  /// names another or [episodeId] moves it to another episode (then it is
  /// that episode's event).
  void updateEvent(
    int id, {
    int? episodeId,
    String? card,
    required DateTime date,
    int? timeMinutes,
    required String title,
    String? note,
    bool rest = false,
  }) {
    final place = _eventPlace(episodeId, card);
    _checkEvent(timeMinutes, place.episode, rest);
    db.execute(
      '''
UPDATE events SET
  part_id = CASE WHEN ?2 THEN ?3 WHEN episode_id IS ?1 THEN part_id END,
  stage_id = CASE WHEN ?2 THEN ?4 WHEN episode_id IS ?1 THEN stage_id END,
  episode_id = ?1, day = ?5, time_min = ?6, title = ?7, note = ?8, rest = ?9
WHERE id = ?10;''',
      [
        place.episode,
        if (card != null) 1 else 0,
        place.part,
        place.stage,
        _day(date),
        timeMinutes,
        title,
        note,
        if (rest) 1 else 0,
        id,
      ],
    );
  }

  /// Where an event goes: the card's episode, part and stage, or just
  /// [episodeId]. Only part × stage and part-less cards take events.
  ({int? episode, int? part, int? stage}) _eventPlace(
    int? episodeId,
    String? card,
  ) {
    if (card == null) return (episode: episodeId, part: null, stage: null);
    final k = card.split(':');
    final ({int? episode, int? part, int? stage}) place;
    switch (k) {
      case ['part', final p, final st]:
        final part = int.parse(p);
        final row = db.select('SELECT episode_id FROM parts WHERE id = ?;', [
          part,
        ]);
        if (row.isEmpty) throw ArgumentError.value(card, 'card', 'no part');
        place = (
          episode: row.first['episode_id'] as int,
          part: part,
          stage: int.parse(st),
        );
      case ['nopart', final e, final st]:
        place = (episode: int.parse(e), part: null, stage: int.parse(st));
      default:
        throw ArgumentError.value(card, 'card', 'not a part or episode card');
    }
    if (episodeId != null && episodeId != place.episode) {
      throw ArgumentError('Card $card is not on episode $episodeId.');
    }
    return place;
  }

  void deleteEvent(int id) =>
      db.execute('DELETE FROM events WHERE id = ?;', [id]);

  /// Events on the local days from [from] up to (not including) [to],
  /// grouped by episode (null: events on no episode); each list by day,
  /// all-day ones first, then by time. Events of archived episodes are
  /// left out.
  ///
  /// Card events are not here but in [cardEvents].
  Map<int?, List<EventRow>> events({
    required DateTime from,
    required DateTime to,
  }) {
    final out = <int?, List<EventRow>>{};
    for (final e in _events(from, to, cards: false)) {
      (out[e.episodeId] ??= []).add(e);
    }
    return out;
  }

  /// Card events (유저 2026-11-28 정정) on the local days from [from] up
  /// to [to], by card (`PartGroup.key`), ordered as [events]. A collapsed
  /// row finds its cards' events by their keys. Events of archived
  /// episodes, works and parts are left out.
  Map<String, List<EventRow>> cardEvents({
    required DateTime from,
    required DateTime to,
  }) {
    final out = <String, List<EventRow>>{};
    for (final e in _events(from, to, cards: true)) {
      (out[e.card!] ??= []).add(e);
    }
    return out;
  }

  List<EventRow> _events(DateTime from, DateTime to, {required bool cards}) {
    final rows = db.select(
      '''
SELECT ev.id, ev.episode_id, ev.part_id, ev.stage_id, ev.day, ev.time_min,
       ev.title, ev.note, ev.rest
FROM events ev LEFT JOIN episodes e ON e.id = ev.episode_id
LEFT JOIN works w ON w.id = e.work_id
LEFT JOIN parts p ON p.id = ev.part_id
WHERE ev.day >= ?1 AND ev.day < ?2
  AND (ev.stage_id IS NOT NULL) = ?3
  AND (ev.episode_id IS NULL
       OR (e.archived_at IS NULL AND w.archived_at IS NULL))
  AND (p.id IS NULL OR p.archived_at IS NULL)
ORDER BY ev.day, ev.time_min, ev.id;''', // NULL (all day) sorts first
      [_day(from), _day(to), if (cards) 1 else 0],
    );
    return [
      for (final r in rows)
        (
          id: r['id'] as int,
          episodeId: r['episode_id'] as int?,
          card: switch ((r['stage_id'], r['part_id'])) {
            (null, _) => null,
            (final s, null) => 'nopart:${r['episode_id']}:$s',
            (final s, final p) => 'part:$p:$s',
          },
          date: _dayOf(r['day'] as String),
          timeMinutes: r['time_min'] as int?,
          title: r['title'] as String,
          note: r['note'] as String?,
          rest: r['rest'] == 1,
        ),
    ];
  }

  static DateTime _dayOf(String day) {
    final d = day.split('-').map(int.parse).toList();
    return DateTime(d[0], d[1], d[2]);
  }

  static String _day(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}';
  }

  static void _checkEvent(int? minutes, int? episodeId, bool rest) {
    if (minutes != null) {
      RangeError.checkValueInInterval(minutes, 0, 24 * 60 - 1, 'timeMinutes');
    }
    if (rest && episodeId != null) {
      throw ArgumentError('A day off is an event of no episode.');
    }
  }

  /// An episode's cuts in number order — live ones, plus archived ones
  /// (taken-out numbers, to restore on the grid) with [includeArchived].
  /// Cuts of an archived part are left out.
  List<CutRow> cuts(int episodeId, {bool includeArchived = false}) {
    final labels = _sharedLabels();
    final style = settings.cutStyle;
    return [
      for (final r in db.select(
        'SELECT c.id, c.number, c.length_ms, c.part_id, c.shared_with, '
        'c.archived_at IS NOT NULL AS archived FROM cuts c '
        'LEFT JOIN parts p ON p.id = c.part_id '
        'WHERE c.episode_id = ? AND (? OR c.archived_at IS NULL) '
        'AND (p.id IS NULL OR p.archived_at IS NULL) ORDER BY c.sort_key, c.id;',
        [episodeId, if (includeArchived) 1 else 0],
      ))
        _cutRow(r, labels, style),
    ];
  }

  static CutRow _cutRow(Row r, Map<int, String> labels, NumberStyle style) {
    final id = r['id'] as int;
    final archived = r['archived'] == 1;
    final head = archived
        ? null
        : (r['shared_with'] as int?) ?? (labels.containsKey(id) ? id : null);
    return (
      id: id,
      number: shownNumber(r['number'] as String, style),
      lengthMs: r['length_ms'] as int?,
      partId: r['part_id'] as int?,
      sharedHeadCutId: head,
      sharedLabel: head == null ? null : labels[head],
      archived: archived,
    );
  }

  /// All timer time on each of [taskIds] as of now, a running timer
  /// included. Tasks with no time are absent.
  Map<int, Duration> workedOn(Iterable<int> taskIds) {
    final ids = taskIds.toSet();
    if (ids.isEmpty) return const {};
    final rows = db.select(
      'SELECT task_id, SUM(MAX(COALESCE(stopped_at, ?) - started_at, 0)) AS ms '
      'FROM work_intervals WHERE task_id IN (${List.filled(ids.length, '?').join(',')}) '
      'GROUP BY task_id;',
      [_now(), ...ids],
    );
    return {
      for (final r in rows)
        r['task_id'] as int: Duration(milliseconds: r['ms'] as int),
    };
  }

  /// Every timer stretch on [taskId], oldest first (a running one last).
  List<WorkInterval> intervalsOf(int taskId) => [
    for (final r in db.select(
      'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
      'WHERE task_id = ? ORDER BY started_at, id;',
      [taskId],
    ))
      WorkInterval(
        id: r['id'] as int,
        start: _utc(r['started_at'] as int),
        stop: _utcOrNull(r['stopped_at']),
        taskId: taskId,
      ),
  ];

  /// The other tasks the timer can move to from [taskId]: the live tasks
  /// of the same episode, in display order (each row carries its part).
  List<TaskRow> tasksBeside(int taskId) {
    final rows = taskRows(includeDone: true);
    final me = rows.where((t) => t.id == taskId).firstOrNull;
    if (me == null) return const [];
    return [
      for (final t in rows)
        if (t.episodeId == me.episodeId && t.id != taskId) t,
    ];
  }

  /// The task the timer was last pointed at (유저 2026-11-28: the same cut
  /// after a relaunch, kept in the document), or null when none was, or
  /// it has since gone — deleted, handed off, or submitted.
  int? timerTarget() {
    final id = settings.timerTargetId;
    if (id == null) return null;
    final live = db.select(
      'SELECT 1 FROM live_tasks WHERE id = ? AND handed_off_at IS NULL '
      "AND status <> 'submitted';",
      [id],
    );
    return live.isEmpty ? null : id;
  }

  /// Remembers [taskId] as the timer's target; null forgets it.
  void setTimerTarget(int? taskId) => settings.timerTargetId = taskId;

  /// The running timer, if any.
  WorkInterval? runningTimer() {
    final rows = db.select(
      'SELECT id, started_at, task_id FROM work_intervals '
      'WHERE stopped_at IS NULL ORDER BY started_at DESC LIMIT 1;',
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return WorkInterval(
      id: r['id'] as int,
      start: _utc(r['started_at'] as int),
      taskId: r['task_id'] as int?,
    );
  }

  /// The statistics tab for the work days `[from, to)` (local dates),
  /// bucketed by [bucket], narrowed to [clientId] and/or [workId] when
  /// given (timer time on no task then drops out), with [Stats.previous] = the same length just
  /// before and [Stats.stagePaces]. Day start, week start and lane count
  /// come from the settings.
  Stats stats({
    required DateTime from,
    required DateTime to,
    StatsBucket bucket = StatsBucket.week,
    int? clientId,
    int? workId,
  }) {
    from = DateTime(from.year, from.month, from.day);
    to = DateTime(to.year, to.month, to.day);
    final days = to.difference(from).inHours ~/ 24;
    // The facts do not depend on the period: read them once for both.
    final facts = _statsFacts(clientId, workId);
    final filtered = clientId != null || workId != null;
    final current = _stats(facts, from, to, bucket, filtered: filtered);
    current.previous = _stats(
      facts,
      DateTime(from.year, from.month, from.day - days),
      from,
      bucket,
      filtered: filtered,
    );
    current.stagePaces = stagePaces();
    return current;
  }

  /// Every task the statistics count (finished and handed-off ones too),
  /// with its client, for [clientId] / [workId] when given.
  List<StatsFact> _statsFacts(int? clientId, int? workId) {
    final extra = {
      for (final r in db.select('''
SELECT t.id, t.submitted_at, t.submitted_due_at, w.client_id,
       c.name AS client
FROM live_tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN clients c ON c.id = w.client_id;'''))
        r['id'] as int: r,
    };
    return [
      for (final t in taskRows(
        workId: workId,
        includeDone: true,
        includeHandedOff: true,
      ))
        if (extra[t.id] case final x?)
          if (clientId == null || x['client_id'] == clientId)
            StatsFact(
              taskId: t.id,
              stageName: t.stageName,
              workId: t.workId,
              workTitle: t.workTitle,
              currency: t.currency,
              groupKey: t.groupKey,
              unitKey: t.unitKey,
              episodeId: t.episodeId,
              episodeLabel: t.episodeNumber,
              partId: t.partId,
              partLabel: t.partLabel,
              cutKey: t.cutId != null ? '${t.cutId}' : 's${t.id}',
              cutLabel: t.unitLabel,
              status: t.status,
              clientId: x['client_id'] as int?,
              clientName: x['client'] as String?,
              clientColor: t.clientColor,
              take: t.take,
              submittedAt: _utcOrNull(x['submitted_at']),
              dueAt: t.dueAt,
              submittedDueAt: _utcOrNull(x['submitted_due_at']),
              firstDueAt: t.firstDueAt,
              dueExtensions: t.dueExtensions,
              handedOffAt: t.handedOffAt,
              planStartAt: t.planStartAt,
              planEndAt: t.planEndAt,
              pay: t.pay,
              worked: t.worked,
            ),
    ];
  }

  /// The statistics drill-down for the work days `[from, to)` (유저
  /// 2026-11-28): client → work → episode → unit → cut, every node with
  /// the figures of a [StatsSlice] (the root's equal [stats]' total), cut
  /// leaves with their task's details. Narrowed like [stats].
  StatsNode statsTree({
    required DateTime from,
    required DateTime to,
    int? clientId,
    int? workId,
  }) => _stats(
    _statsFacts(clientId, workId),
    DateTime(from.year, from.month, from.day),
    DateTime(to.year, to.month, to.day),
    StatsBucket.month,
    filtered: clientId != null || workId != null,
    tree: true,
  ).tree!;

  Stats _stats(
    List<StatsFact> facts,
    DateTime from,
    DateTime to,
    StatsBucket bucket, {
    required bool filtered,
    bool tree = false,
  }) {
    final dayStart = settings.dayStartMinutes;
    final start = DateTime(
      from.year,
      from.month,
      from.day,
    ).add(Duration(minutes: dayStart));
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(Duration(minutes: dayStart));
    final taskIds = {for (final f in facts) f.taskId};
    final intervals = [
      for (final r in db.select(
        'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
        'WHERE started_at < ? AND (stopped_at IS NULL OR stopped_at > ?);',
        [end.millisecondsSinceEpoch, start.millisecondsSinceEpoch],
      ))
        WorkInterval(
          id: r['id'] as int,
          start: _utc(r['started_at'] as int),
          stop: _utcOrNull(r['stopped_at']),
          taskId: r['task_id'] as int?,
        ),
    ].where((i) => !filtered || taskIds.contains(i.taskId)).toList();
    return computeStats(
      facts: facts,
      intervals: intervals,
      from: from,
      to: to,
      now: clock().toUtc(),
      bucket: bucket,
      dayStartMinutes: dayStart,
      weekStart: settings.weekStart,
      lanes: settings.parallelLanes,
      tree: tree,
    );
  }

  /// Timer time per working day for the week holding [weekOf] (today when
  /// null), starting on the week-start setting, days cut at the day-start
  /// setting. A running timer counts up to now.
  List<({DateTime day, Duration worked})> weekHours({DateTime? weekOf}) {
    final now = clock();
    final dayStart = settings.dayStartMinutes;
    final anchor = dayRange(weekOf ?? now, dayStart).start;
    final back = (anchor.weekday - settings.weekStart) % 7;
    final first = DateTime(anchor.year, anchor.month, anchor.day - back);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(first.year, first.month, first.day + i),
    ];
    DateTime startOf(DateTime d) => d.add(Duration(minutes: dayStart));
    final from = startOf(days.first);
    final to = startOf(
      DateTime(days.last.year, days.last.month, days.last.day + 1),
    );
    final spans = _intervals(from, to);
    return [
      for (final d in days)
        (
          day: d,
          worked: totalElapsed(
            spans,
            now.toUtc(),
            from: startOf(d).toUtc(),
            to: startOf(DateTime(d.year, d.month, d.day + 1)).toUtc(),
          ),
        ),
    ];
  }

  /// The timer stretches of the working day holding [day] (today when
  /// null), clipped to it, oldest first, with the work they were on.
  List<({DateTime start, DateTime end, bool running, int? workId, int? taskId})>
  dayIntervals({DateTime? day}) {
    final now = clock().toUtc();
    final range = dayRange(day ?? clock(), settings.dayStartMinutes);
    final from = range.start.toUtc();
    final to = range.end.toUtc();
    final rows = db.select(
      '''
SELECT i.started_at, i.stopped_at, i.task_id, s.work_id
FROM work_intervals i
LEFT JOIN tasks t ON t.id = i.task_id
LEFT JOIN work_stages s ON s.id = t.stage_id
WHERE i.started_at < ? AND (i.stopped_at IS NULL OR i.stopped_at > ?)
ORDER BY i.started_at;''',
      [_ms(to), _ms(from)],
    );
    return [
      for (final r in rows)
        if (_clip(
              _utc(r['started_at'] as int),
              r['stopped_at'] == null ? now : _utc(r['stopped_at'] as int),
              from,
              to,
            )
            case (final s, final e))
          (
            start: s,
            end: e,
            running: r['stopped_at'] == null,
            workId: r['work_id'] as int?,
            taskId: r['task_id'] as int?,
          ),
    ];
  }

  static (DateTime, DateTime)? _clip(
    DateTime s,
    DateTime e,
    DateTime from,
    DateTime to,
  ) {
    final a = s.isAfter(from) ? s : from;
    final b = e.isBefore(to) ? e : to;
    return b.isAfter(a) ? (a, b) : null;
  }

  List<WorkInterval> _intervals(DateTime from, DateTime to) => [
    for (final r in db.select(
      'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
      'WHERE started_at < ? AND (stopped_at IS NULL OR stopped_at > ?);',
      [_ms(to), _ms(from)],
    ))
      WorkInterval(
        id: r['id'] as int,
        start: _utc(r['started_at'] as int),
        stop: r['stopped_at'] == null ? null : _utc(r['stopped_at'] as int),
        taskId: r['task_id'] as int?,
      ),
  ];

  /// Hides [id] of [kind] and everything beneath it from the views. The
  /// rows stay; [restore] brings them back.
  void archive(ArchiveKind kind, int id) {
    db.execute(
      'UPDATE ${kind.table} SET archived_at = ? '
      'WHERE id = ? AND archived_at IS NULL;',
      [_now(), id],
    );
  }

  /// Brings back an archived item. Throws [StateError] when a live item
  /// now takes its place (a cut number or a cut × stage reused since).
  void restore(ArchiveKind kind, int id) {
    try {
      db.execute('UPDATE ${kind.table} SET archived_at = NULL WHERE id = ?;', [
        id,
      ]);
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067 || e.resultCode == 19) {
        throw StateError(
          'Cannot restore ${kind.name} $id: a live one now uses its place.',
        );
      }
      rethrow;
    }
  }

  /// Puts the tasks [ids] away (보관) — a card or the selection tool's
  /// pick — out of every view, statistic, pace and timer list, as
  /// [archive] does for one. [restoreTasks] brings them back. Other units
  /// keep their lanes and order.
  void archiveTasks(Iterable<int> ids) => _transaction(() {
    _holdBeforeDates();
    db.execute(
      'UPDATE tasks SET archived_at = ? WHERE archived_at IS NULL '
      'AND id $_inJson;',
      [_now(), _idList(ids)],
    );
  });

  /// Brings archived tasks [ids] back, all or none. Throws [StateError]
  /// when a live task now holds the same cut × stage.
  void restoreTasks(Iterable<int> ids) => _transaction(() {
    _holdBeforeDates();
    try {
      db.execute('UPDATE tasks SET archived_at = NULL WHERE id $_inJson;', [
        _idList(ids),
      ]);
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067 || e.resultCode == 19) {
        throw StateError('Cannot restore: a live task now uses the place.');
      }
      rethrow;
    }
  });

  /// What [deleteTasks] of [ids] would take away.
  DeletionSummary deletionSummary(Iterable<int> ids) {
    final plan = _DeletionPlan.of(db, _idList(ids));
    final ms =
        db.select(
              'SELECT COALESCE(SUM(MAX(COALESCE(stopped_at, ?) - started_at, '
              '0)), 0) AS ms FROM work_intervals WHERE task_id $_inJson;',
              [_now(), plan.tasks],
            ).first['ms']
            as int;
    return (
      tasks: plan.taskIds.length,
      cuts: plan.cutCount,
      episodes: plan.episodeIds.length,
      works: plan.workIds.length,
      timerMinutes: ms ~/ Duration.millisecondsPerMinute,
    );
  }

  /// Deletes the tasks [ids] for good (완전 삭제), in one transaction, with
  /// everything that hangs off them: timer stretches, retakes, deadline
  /// revisions, the timer target; and, for a unit (part × stage, …) left
  /// with no task, its deadline, plan, kickoff, hold, lane pin and place
  /// in the order. A cut left with no task goes too, then a part with no
  /// cut, an episode with no cut or storyboard, a work with no episode —
  /// no empty shells. Clients stay. Archived tasks count as tasks: what
  /// still has one stays.
  void deleteTasks(Iterable<int> ids) => _transaction(() {
    final plan = _DeletionPlan.of(db, _idList(ids));
    if (plan.taskIds.isEmpty) return;
    _holdBeforeDates();
    if (plan.taskIds.contains(settings.timerTargetId)) {
      settings.timerTargetId = null;
    }
    // The units the tasks belonged to, read before the tasks go.
    final units = db.select(
      'SELECT t.id, t.stage_id, t.storyboard_id, c.part_id, c.episode_id '
      'FROM tasks t LEFT JOIN cuts c ON c.id = t.cut_id WHERE t.id $_inJson;',
      [plan.tasks],
    );
    for (final table in const ['work_intervals', 'retakes', 'due_revisions']) {
      db.execute('DELETE FROM $table WHERE task_id $_inJson;', [plan.tasks]);
    }
    db.execute('DELETE FROM tasks WHERE id $_inJson;', [plan.tasks]);
    for (final u in units) {
      final stage = u['stage_id'] as int;
      final part = u['part_id'] as int?;
      final episode = u['episode_id'] as int?;
      if (u['storyboard_id'] != null) {
        _forgetPlace('storyboard:${u['id']}');
      } else if (part != null) {
        if (!_unitHasTasks('c.part_id = ?', part, stage)) {
          _deletePartStage(part, stage);
        }
      } else if (!_unitHasTasks(
        'c.part_id IS NULL AND c.episode_id = ?',
        episode!,
        stage,
      )) {
        _forgetPlace('nopart:$episode:$stage');
        db.execute(
          'DELETE FROM events WHERE episode_id = ? AND part_id IS NULL '
          'AND stage_id = ?;',
          [episode, stage],
        );
      }
    }
    db
      ..execute(
        'UPDATE cuts SET shared_with = NULL WHERE shared_with $_inJson;',
        [plan.cuts],
      )
      ..execute('DELETE FROM cuts WHERE id $_inJson;', [plan.cuts])
      ..execute('DELETE FROM storyboards WHERE id $_inJson;', [
        plan.storyboards,
      ]);
    plan.partIds.forEach(_deletePart);
    plan.episodeIds.forEach(_deleteEmptyEpisode);
    for (final work in plan.workIds) {
      db
        ..execute('DELETE FROM work_stages WHERE work_id = ?;', [work])
        ..execute('DELETE FROM works WHERE id = ?;', [work]);
    }
  });

  /// Runs [body] — several writes of one user action — as one: all of it
  /// or, when it throws, none; and one step of the undo history. Nested
  /// batches join the outermost.
  T batch<T>(T Function() body) => _transaction(body);

  /// Whether [id] of [kind] is in use — then it cannot be deleted, only
  /// archived: a client with a work, a work with an episode, an episode
  /// with a cut or storyboard, a part with a cut. Archived ones count.
  bool inUse(CatalogueKind kind, int id) =>
      db.select('SELECT ${_inUseSql(kind, '?1')} AS used;', [
        id,
      ]).first['used'] ==
      1;

  /// SQL for "[kind] [id] is in use" ([id] an SQL expression).
  static String _inUseSql(CatalogueKind kind, String id) => switch (kind) {
    CatalogueKind.work => 'EXISTS (SELECT 1 FROM episodes WHERE work_id = $id)',
    CatalogueKind.episode =>
      'EXISTS (SELECT 1 FROM cuts WHERE episode_id = $id) '
          'OR EXISTS (SELECT 1 FROM storyboards WHERE episode_id = $id)',
    CatalogueKind.part => 'EXISTS (SELECT 1 FROM cuts WHERE part_id = $id)',
    CatalogueKind.client =>
      'EXISTS (SELECT 1 FROM works WHERE client_id = $id)',
  };

  void _checkUnused(CatalogueKind kind, int id) {
    if (inUse(kind, id)) {
      throw StateError('${kind.name} $id is in use; archive it instead.');
    }
  }

  /// Deletes a client no work uses. Throws [StateError] when one does.
  void deleteClient(int id) => _transaction(() {
    _checkUnused(CatalogueKind.client, id);
    db.execute('DELETE FROM clients WHERE id = ?;', [id]);
  });

  /// Deletes a work with no episode, and its stages. Throws [StateError]
  /// when it has one.
  void deleteWork(int id) => _transaction(() {
    _checkUnused(CatalogueKind.work, id);
    db
      ..execute('DELETE FROM work_stages WHERE work_id = ?;', [id])
      ..execute('DELETE FROM works WHERE id = ?;', [id]);
  });

  /// Deletes an episode with no cut or storyboard, with its (empty)
  /// parts, rates and events. Throws [StateError] when it has one.
  void deleteEpisode(int id) => _transaction(() {
    _checkUnused(CatalogueKind.episode, id);
    _deleteEmptyEpisode(id);
  });

  /// Deletes a part with no cut, and its per-stage rows. Throws
  /// [StateError] when it has one.
  void deletePart(int id) => _transaction(() {
    _checkUnused(CatalogueKind.part, id);
    _holdBeforeDates();
    _deletePart(id);
  });

  void _deleteEmptyEpisode(int episode) {
    for (final r in db.select('SELECT id FROM parts WHERE episode_id = ?;', [
      episode,
    ])) {
      _deletePart(r['id'] as int);
    }
    _forgetPlaces('nopart:$episode:%');
    db
      ..execute('DELETE FROM episode_rates WHERE episode_id = ?;', [episode])
      // Its events go by ON DELETE CASCADE.
      ..execute('DELETE FROM episodes WHERE id = ?;', [episode]);
  }

  /// Whether the cuts matching [where] (one `?`, [id]) still have a task
  /// of [stage], archived ones included.
  bool _unitHasTasks(String where, int id, int stage) => db.select(
    'SELECT 1 FROM tasks t JOIN cuts c ON c.id = t.cut_id '
    'WHERE $where AND t.stage_id = ? LIMIT 1;',
    [id, stage],
  ).isNotEmpty;

  /// A part left with no cut, and every per-stage row it has.
  void _deletePart(int part) {
    for (final table in _partStageTables) {
      db.execute('DELETE FROM $table WHERE part_id = ?;', [part]);
    }
    _forgetPlaces('part:$part:%');
    db.execute('DELETE FROM parts WHERE id = ?;', [part]);
  }

  /// A part × stage left with no task: its deadline and revisions, plan,
  /// kickoff, hold and place.
  void _deletePartStage(int part, int stage) {
    for (final table in _partStageTables) {
      db.execute('DELETE FROM $table WHERE part_id = ? AND stage_id = ?;', [
        part,
        stage,
      ]);
    }
    _forgetPlace('part:$part:$stage');
  }

  static const _partStageTables = [
    'events', // the card's events
    'part_stage_dues',
    'part_stage_plans',
    'part_stage_kickoffs',
    'part_stage_waits',
    'due_revisions',
  ];

  /// Drops the lane pin and manual order of the unit [key].
  void _forgetPlace(String key) {
    db
      ..execute('DELETE FROM group_order WHERE group_key = ?;', [key])
      ..execute('DELETE FROM lane_pins WHERE group_key = ?;', [key]);
  }

  /// [_forgetPlace] for every unit whose key matches the LIKE [pattern].
  void _forgetPlaces(String pattern) {
    db
      ..execute('DELETE FROM group_order WHERE group_key LIKE ?;', [pattern])
      ..execute('DELETE FROM lane_pins WHERE group_key LIKE ?;', [pattern]);
  }

  /// SQL for "in the JSON id list bound here".
  static const _inJson = 'IN (SELECT value FROM json_each(?))';

  static String _idList(Iterable<int> ids) => '[${ids.join(',')}]';

  /// Archived items, newest first, with a label to show: works by title,
  /// episodes by number, parts by label, cuts by number, storyboards by
  /// label, tasks by "cut or storyboard · stage", stages by name.
  List<({ArchiveKind kind, int id, String label, DateTime archivedAt})>
  archived() {
    // Each label is [pre] [episode] [cut] + post; numbers are shown in
    // the current styles here, not in SQL.
    final rows = db.select('''
SELECT 'work' AS kind, id, title AS pre, NULL AS ep, NULL AS cut, '' AS post,
    archived_at FROM works
  WHERE archived_at IS NOT NULL
UNION ALL SELECT 'episode', e.id, w.title, e.number, NULL, '', e.archived_at
  FROM episodes e JOIN works w ON w.id = e.work_id
  WHERE e.archived_at IS NOT NULL
UNION ALL SELECT 'part', p.id, NULL, e.number, NULL, ' ' || p.label,
    p.archived_at
  FROM parts p JOIN episodes e ON e.id = p.episode_id
  WHERE p.archived_at IS NOT NULL
UNION ALL SELECT 'cut', c.id, NULL, e.number, c.number, '', c.archived_at
  FROM cuts c JOIN episodes e ON e.id = c.episode_id
  WHERE c.archived_at IS NOT NULL
UNION ALL SELECT 'storyboard', sb.id, NULL, e.number, NULL, ' ' || sb.label,
    sb.archived_at
  FROM storyboards sb JOIN episodes e ON e.id = sb.episode_id
  WHERE sb.archived_at IS NOT NULL
UNION ALL SELECT 'task', t.id, sb.label, NULL, c.number, ' · ' || s.name,
    t.archived_at
  FROM tasks t JOIN work_stages s ON s.id = t.stage_id
  LEFT JOIN cuts c ON c.id = t.cut_id
  LEFT JOIN storyboards sb ON sb.id = t.storyboard_id
  WHERE t.archived_at IS NOT NULL
UNION ALL SELECT 'stage', s.id, w.title || ' · ' || s.name, NULL, NULL, '',
    s.archived_at
  FROM work_stages s JOIN works w ON w.id = s.work_id
  WHERE s.archived_at IS NOT NULL
ORDER BY 7 DESC, 1, 2;''');
    final cutStyle = settings.cutStyle;
    final episodeStyle = settings.episodeStyle;
    String label(Row r) {
      final ep = r['ep'] as String?;
      final cut = r['cut'] as String?;
      return [
            r['pre'] as String?,
            if (ep != null) shownNumber(ep, episodeStyle),
            if (cut != null) shownNumber(cut, cutStyle),
          ].nonNulls.join(' ') +
          (r['post'] as String);
    }

    return [
      for (final r in rows)
        (
          kind: ArchiveKind.values.byName(r['kind'] as String),
          id: r['id'] as int,
          label: label(r),
          archivedAt: _utc(r['archived_at'] as int),
        ),
    ];
  }

  /// Adds a stage to a work's own list, at the end or before
  /// [beforeStageId], and returns its id. Presets are not touched.
  int addStage(int workId, String name, {int? beforeStageId}) =>
      _transaction(() {
        final ids = [for (final s in stages(workId)) s.id];
        var at = ids.length;
        if (beforeStageId != null) {
          at = ids.indexOf(beforeStageId);
          if (at < 0) {
            throw ArgumentError.value(beforeStageId, 'beforeStageId');
          }
        }
        db.execute(
          'INSERT INTO work_stages (work_id, name, position) VALUES (?, ?, 0);',
          [workId, name],
        );
        final id = db.lastInsertRowId;
        _setOrder([...ids.take(at), id, ...ids.skip(at)]);
        return id;
      });

  void renameStage(int stageId, String name) => db.execute(
    'UPDATE work_stages SET name = ? WHERE id = ?;',
    [name, stageId],
  );

  /// Puts a work's live stages in the order of [stageIds], which must be
  /// exactly those stages.
  void reorderStages(int workId, List<int> stageIds) => _transaction(() {
    final live = {for (final s in stages(workId)) s.id};
    if (stageIds.length != live.length || !live.containsAll(stageIds)) {
      throw ArgumentError('Give every live stage of the work exactly once.');
    }
    _setOrder(stageIds);
  });

  void _setOrder(List<int> stageIds) {
    for (var i = 0; i < stageIds.length; i++) {
      db.execute('UPDATE work_stages SET position = ? WHERE id = ?;', [
        i,
        stageIds[i],
      ]);
    }
  }

  /// Adds a part (a bundle of the user's cuts) to an episode. The cut
  /// count may be known before the cuts themselves.
  int addPart(int episodeId, String label, {int? plannedCutCount}) {
    db.execute(
      'INSERT INTO parts (episode_id, label, sort_key, planned_cut_count) '
      'VALUES (?, ?, ?, ?);',
      [episodeId, label, naturalSortKey(label), plannedCutCount],
    );
    return db.lastInsertRowId;
  }

  /// Sets the part's deadline for a stage; its cut tasks follow it unless
  /// they carry their own.
  ///
  /// Corrects the deadline in force (its last revision; the first when
  /// there is none). A new revision — an extension — is [extendDue].
  void setPartDue(int partId, int stageId, DateTime dueAt) => _transaction(
    () => _setCurrentDue(DueTarget.part(partId, stageId), dueAt),
  );

  /// Creates a task for [stageId] on every live cut of the part that does
  /// not have one yet, and returns the new task ids.
  List<int> addTasksForPart(int partId, int stageId) => _transaction(() {
    final cuts = db.select(
      'SELECT c.id FROM cuts c WHERE c.part_id = ? AND c.archived_at IS NULL '
      'AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.cut_id = c.id '
      'AND t.stage_id = ? AND t.archived_at IS NULL) ORDER BY c.sort_key, c.id;',
      [partId, stageId],
    );
    if (cuts.isEmpty) return const <int>[];
    // One statement for all cuts; then the part's default kickoff once.
    final now = _now();
    final insert = db.prepare(
      'INSERT INTO tasks (stage_id, cut_id, received_at) VALUES (?, ?, ?);',
    );
    final ids = <int>[];
    try {
      for (final c in cuts) {
        insert.execute([stageId, c['id'], now]);
        ids.add(db.lastInsertRowId);
      }
    } finally {
      insert.close();
    }
    _defaultKickoff(ids.first);
    return ids;
  });

  /// The task's deadline: its own, else its part's for the stage.
  ({DateTime? dueAt, bool fromPart}) dueFor(int taskId) {
    final r = db.select(
      'SELECT due_at, from_part FROM task_dues WHERE task_id = ?;',
      [taskId],
    ).first;
    final ms = r['due_at'] as int?;
    return (dueAt: ms == null ? null : _utc(ms), fromPart: r['from_part'] == 1);
  }

  int addStoryboard(int episodeId, String label) {
    db.execute('INSERT INTO storyboards (episode_id, label) VALUES (?, ?);', [
      episodeId,
      label,
    ]);
    return db.lastInsertRowId;
  }

  void setEpisodeRate(int episodeId, int stageId, Rate rate) => db.execute(
    'INSERT INTO episode_rates (episode_id, stage_id, unit, amount) '
    'VALUES (?, ?, ?, ?) ON CONFLICT (episode_id, stage_id) '
    'DO UPDATE SET unit = excluded.unit, amount = excluded.amount;',
    [episodeId, stageId, rate.unit.dbName, rate.amount],
  );

  /// Adds a task for one stage of a cut or a storyboard (exactly one).
  int addTask(
    int stageId, {
    int? cutId,
    int? storyboardId,
    DateTime? dueAt,
    Rate? rate,
  }) {
    db.execute(
      'INSERT INTO tasks (stage_id, cut_id, storyboard_id, received_at, '
      'due_at, rate_unit, rate_amount) VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        stageId,
        cutId,
        storyboardId,
        _now(),
        dueAt?.millisecondsSinceEpoch,
        rate?.unit.dbName,
        rate?.amount,
      ],
    );
    final id = db.lastInsertRowId;
    if (dueAt != null) {
      db.execute(
        'INSERT INTO due_revisions (task_id, revision, due_at, created_at) '
        'VALUES (?, 1, ?, ?);',
        [id, _ms(dueAt), _now()],
      );
    }
    _defaultKickoff(id);
    return id;
  }

  /// A new task's production kickoff defaults to the day it was entered:
  /// on its part × stage when the cut is in a part (unless the part
  /// already has one), else on the task itself.
  void _defaultKickoff(int taskId) {
    final day = dayRange(clock(), settings.dayStartMinutes).start;
    final at = _ms(DateTime(day.year, day.month, day.day));
    db
      ..execute(
        '''
INSERT OR IGNORE INTO part_stage_kickoffs (part_id, stage_id, kickoff_at)
SELECT c.part_id, t.stage_id, ? FROM tasks t JOIN cuts c ON c.id = t.cut_id
WHERE t.id = ? AND c.part_id IS NOT NULL;''',
        [at, taskId],
      )
      ..execute(
        '''
UPDATE tasks SET kickoff_at = ? WHERE id = ? AND kickoff_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM cuts c WHERE c.id = tasks.cut_id
                  AND c.part_id IS NOT NULL);''',
        [at, taskId],
      );
  }

  /// Sets [status]. `submitted_at` is when the cut was FIRST handed in —
  /// finished, paid and counted once by pace, totals and statistics
  /// (2026-11-28 유저: 완료와 제출 합침); handing in a retake stamps that
  /// take's row instead.
  ///
  /// A shared (겸용) cut is one cut in progress (유저 2026-11-28): the
  /// status goes to the same stage's task of every live cut in its group.
  void setStatus(int taskId, TaskStatus status) => _transaction(() {
    _sharedSiblings(taskId).forEach((id) => _setOneStatus(id, status));
    _setOneStatus(taskId, status);
  });

  /// The same stage's live tasks on the other live cuts of [taskId]'s
  /// shared (겸용) group; empty for a cut in no group.
  List<int> _sharedSiblings(int taskId) => [
    for (final r in db.select(
      '''
SELECT t2.id FROM tasks t JOIN cuts c ON c.id = t.cut_id
JOIN cuts c2 ON c2.archived_at IS NULL
  AND COALESCE(c2.shared_with, c2.id) = COALESCE(c.shared_with, c.id)
JOIN live_tasks t2 ON t2.cut_id = c2.id AND t2.stage_id = t.stage_id
WHERE t.id = ?1 AND t2.id <> ?1;''',
      [taskId],
    ))
      r['id'] as int,
  ];

  /// A shared group's head cut (the first) for cut row [c], or NULL when
  /// the cut is in no group with a live other cut.
  static String _sharedHeadSql(String c) =>
      '''
CASE WHEN $c.shared_with IS NOT NULL OR EXISTS (
  SELECT 1 FROM cuts m WHERE m.shared_with = $c.id AND m.archived_at IS NULL)
THEN COALESCE($c.shared_with, $c.id) END''';

  /// `TaskRow.unitKey` in SQL, for task row [t] and its cut row [c]: what
  /// counts as one cut.
  static String _unitKeySql(String t, String c) =>
      "COALESCE('h' || $t.stage_id || ':' || ${_sharedHeadSql(c)}, "
      "'t' || $t.id)";

  void _setOneStatus(int taskId, TaskStatus status) {
    final now = _now();
    final submitted = status == TaskStatus.submitted ? 1 : 0;
    _transaction(() {
      if (submitted == 1) {
        // Out of hand: a timer running on it pauses.
        db.execute(
          'UPDATE work_intervals SET stopped_at = MAX(?, started_at) '
          'WHERE stopped_at IS NULL AND task_id = ?;',
          [now, taskId],
        );
        db.execute(
          '''
UPDATE retakes SET submitted_at = ?
WHERE task_id = ? AND submitted_at IS NULL
  AND take = (SELECT MAX(take) FROM retakes WHERE task_id = ?);''',
          [now, taskId, taskId],
        );
      }
      if (submitted == 1) {
        db.execute(
          '''
UPDATE tasks SET submitted_due_at =
  (SELECT due_at FROM task_dues WHERE task_id = tasks.id)
WHERE id = ? AND submitted_at IS NULL;''',
          [taskId],
        );
      }
      db.execute(
        'UPDATE tasks SET status = ?, '
        'submitted_at = CASE WHEN ? THEN COALESCE(submitted_at, ?) '
        'ELSE submitted_at END '
        'WHERE id = ?;',
        [status.dbName, submitted, now, taskId],
      );
    });
  }

  /// Records the next take (2, 3, …) and moves the task to retake.
  /// Free unless [paidAmount] is given.
  ///
  /// A shared (겸용) cut is retaken whole (유저 2026-11-28): every live cut
  /// of its group gets the stage's next take too, and with [paidAmount]
  /// each of them is paid at its own rate (its task's pay without
  /// retakes; [paidAmount] when that is unknown).
  int requestRetake(int taskId, {DateTime? dueAt, int? paidAmount}) =>
      _transaction(() {
        for (final other in _sharedSiblings(taskId)) {
          _retakeOne(
            other,
            dueAt,
            paidAmount == null ? null : _basePay(other) ?? paidAmount,
          );
        }
        return _retakeOne(taskId, dueAt, paidAmount);
      });

  int _retakeOne(int taskId, DateTime? dueAt, int? paidAmount) {
    final take =
        db.select(
              'SELECT COALESCE(MAX(take), 1) + 1 AS t FROM retakes '
              'WHERE task_id = ?;',
              [taskId],
            ).first['t']
            as int;
    db
      ..execute(
        'INSERT INTO retakes (task_id, take, received_at, due_at, paid, '
        'amount) VALUES (?, ?, ?, ?, ?, ?);',
        [
          taskId,
          take,
          _now(),
          dueAt?.millisecondsSinceEpoch,
          if (paidAmount == null) 0 else 1,
          paidAmount,
        ],
      )
      ..execute("UPDATE tasks SET status = 'retake' WHERE id = ?;", [taskId]);
    return take;
  }

  /// The task's rate: its own override, else its episode's rate for the
  /// stage, else null.
  Rate? rateFor(int taskId) {
    final rows = db.select(
      '''
SELECT COALESCE(t.rate_unit, r.unit) AS unit,
       COALESCE(t.rate_amount, r.amount) AS amount
FROM tasks t
LEFT JOIN cuts c ON c.id = t.cut_id
LEFT JOIN storyboards s ON s.id = t.storyboard_id
LEFT JOIN episode_rates r
  ON r.stage_id = t.stage_id
 AND r.episode_id = COALESCE(c.episode_id, s.episode_id)
WHERE t.id = ?;''',
      [taskId],
    );
    if (rows.isEmpty || rows.first['unit'] == null) return null;
    return Rate(
      RateUnit.fromDb(rows.first['unit'] as String),
      rows.first['amount'] as int,
    );
  }

  /// Pay for the task itself plus its paid retakes, or null if the rate or
  /// (for per-second rates) the cut length is missing.
  int? payFor(int taskId) {
    final base = _basePay(taskId);
    if (base == null) return null;
    final extra =
        db.select(
              'SELECT COALESCE(SUM(amount), 0) AS s FROM retakes '
              'WHERE task_id = ? AND paid = 1;',
              [taskId],
            ).first['s']
            as int;
    return base + extra;
  }

  /// The task's pay at its rate, retakes left out; null like [payFor].
  int? _basePay(int taskId) {
    final rate = rateFor(taskId);
    if (rate == null) return null;
    final row = db.select(
      'SELECT c.length_ms, w.seconds_rounding FROM tasks t '
      'LEFT JOIN cuts c ON c.id = t.cut_id '
      'JOIN work_stages s ON s.id = t.stage_id '
      'JOIN works w ON w.id = s.work_id WHERE t.id = ?;',
      [taskId],
    ).first;
    return rate.payFor(
      lengthMs: row['length_ms'] as int?,
      rounding: _rounding(row['seconds_rounding'], settings.secondsRounding),
    );
  }

  /// Pay for tasks completed in the billing period that closes in
  /// [year]/[month], per currency (no conversion). Each client's own
  /// closing day applies; works without a client close at month end.
  /// `unpriced` counts completed tasks whose pay cannot be computed yet.
  Map<String, ({int total, int unpriced})> monthlyTotals(int year, int month) {
    final closingDays = {
      null,
      for (final r in db.select(
        'SELECT DISTINCT closing_day FROM clients WHERE closing_day IS NOT NULL;',
      ))
        r['closing_day'] as int,
    };
    final totals = <String, ({int total, int unpriced})>{};
    for (final day in closingDays) {
      final p = billingPeriod(year, month, day);
      final rows = db.select(
        '''
SELECT t.id, w.currency FROM live_tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN clients cl ON cl.id = w.client_id
WHERE t.submitted_at >= ? AND t.submitted_at < ?
  AND t.handed_off_at IS NULL
  AND cl.closing_day IS ?;''',
        [
          p.start.toUtc().millisecondsSinceEpoch,
          p.end.toUtc().millisecondsSinceEpoch,
          day,
        ],
      );
      for (final r in rows) {
        final currency = r['currency'] as String;
        final pay = payFor(r['id'] as int);
        final prev = totals[currency] ?? (total: 0, unpriced: 0);
        totals[currency] = pay == null
            ? (total: prev.total, unpriced: prev.unpriced + 1)
            : (total: prev.total + pay, unpriced: prev.unpriced);
      }
    }
    return totals;
  }

  /// Every live task of live works with what the views show, in display
  /// order (work, episode, part, stage, cut). One query: rates, lengths,
  /// takes, paid retakes and timer time are resolved in SQL.
  ///
  /// Unless [includeDone], a submitted task is left out when every task of
  /// its group is submitted too — finished units drop off the views, while
  /// a submitted cut still counts in a part that has open ones ("3/6").
  ///
  /// Tasks handed off to someone else are left out unless
  /// [includeHandedOff]; archived tasks (of live cuts, parts, episodes and
  /// works) unless [includeArchived], marked `archived`.
  List<TaskRow> taskRows({
    int? workId,
    bool includeDone = false,
    bool includeHandedOff = false,
    bool includeArchived = false,
  }) {
    final now = _now();
    final rounding = settings.secondsRounding;
    final rows = db.select(
      '''
WITH open_units AS MATERIALIZED (
  -- (stage, part — or loose episode) units that still have work in hand:
  -- one pass here instead of a search per submitted task.
  SELECT DISTINCT t2.stage_id, c2.part_id,
         CASE WHEN c2.part_id IS NULL THEN c2.episode_id END AS loose_episode
  FROM live_tasks t2 JOIN cuts c2 ON c2.id = t2.cut_id
  WHERE ?3 = 0 AND t2.status <> 'submitted'
)
SELECT t.id, t.status, t.received_at, t.due_at AS own_due,
       d.due_at AS part_due,
       t.plan_start_at AS own_plan_start, t.plan_end_at AS own_plan_end,
       pl.start_at AS part_plan_start, pl.end_at AS part_plan_end,
       t.kickoff_at AS own_kickoff, k.kickoff_at AS part_kickoff,
       COALESCE(tr.n, 0) AS own_revs, tr.first AS own_first,
       COALESCE(pr.n, 0) AS part_revs, pr.first AS part_first,
       t.wait_state, t.wait_reason, t.wait_until,
       pw.part_id IS NOT NULL AS part_waiting, pw.reason AS part_wait_reason,
       pw.until_at AS part_wait_until,
       t.handed_off_at, t.handed_off_note,
       t.archived_at IS NOT NULL AS archived,
       ${_sharedHeadSql('c')} AS shared_head,
       s.id AS stage_id, s.name AS stage_name, s.position AS stage_position,
       w.id AS work_id, w.title, w.currency, w.seconds_rounding,
       cl.name AS client_name, cl.color AS client_color,
       e.id AS episode_id, e.number AS episode_number,
       c.id AS cut_id, c.number AS cut_number, c.length_ms,
       sb.id AS storyboard_id, sb.label AS storyboard_label,
       p.id AS part_id, p.label AS part_label, p.planned_cut_count,
       COALESCE(t.rate_unit, r.unit) AS unit,
       COALESCE(t.rate_amount, r.amount) AS amount,
       (SELECT COALESCE(MAX(take), 1) FROM retakes WHERE task_id = t.id)
         AS take,
       (SELECT COALESCE(SUM(amount), 0) FROM retakes
         WHERE task_id = t.id AND paid = 1) AS extra,
       (SELECT COALESCE(SUM(MAX(COALESCE(stopped_at, ?1) - started_at, 0)), 0)
         FROM work_intervals WHERE task_id = t.id) AS worked_ms
FROM tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN clients cl ON cl.id = w.client_id
LEFT JOIN cuts c ON c.id = t.cut_id
LEFT JOIN storyboards sb ON sb.id = t.storyboard_id
JOIN episodes e ON e.id = COALESCE(c.episode_id, sb.episode_id)
LEFT JOIN parts p ON p.id = c.part_id
LEFT JOIN part_stage_dues d
  ON d.part_id = c.part_id AND d.stage_id = t.stage_id
LEFT JOIN part_stage_kickoffs k
  ON k.part_id = c.part_id AND k.stage_id = t.stage_id
LEFT JOIN part_stage_plans pl
  ON pl.part_id = c.part_id AND pl.stage_id = t.stage_id
LEFT JOIN episode_rates r ON r.episode_id = e.id AND r.stage_id = t.stage_id
LEFT JOIN (SELECT task_id, COUNT(*) AS n,
                  MIN(CASE WHEN revision = 1 THEN due_at END) AS first
           FROM due_revisions WHERE task_id IS NOT NULL GROUP BY task_id) tr
  ON tr.task_id = t.id
LEFT JOIN (SELECT part_id, stage_id, COUNT(*) AS n,
                  MIN(CASE WHEN revision = 1 THEN due_at END) AS first
           FROM due_revisions WHERE task_id IS NULL
           GROUP BY part_id, stage_id) pr
  ON pr.part_id = c.part_id AND pr.stage_id = t.stage_id
LEFT JOIN part_stage_waits pw
  ON pw.part_id = c.part_id AND pw.stage_id = t.stage_id
WHERE (?2 IS NULL OR w.id = ?2)
  AND (?4 = 1 OR t.handed_off_at IS NULL)
  -- the live_tasks conditions, inlined: these joins are already here
  AND (?5 = 1 OR t.archived_at IS NULL) AND w.archived_at IS NULL
  AND e.archived_at IS NULL
  AND (c.id IS NULL OR c.archived_at IS NULL)
  AND (sb.id IS NULL OR sb.archived_at IS NULL)
  AND (p.id IS NULL OR p.archived_at IS NULL)
  AND (?3 = 1 OR t.status <> 'submitted' OR (t.storyboard_id IS NULL AND (
    EXISTS (SELECT 1 FROM open_units o
            WHERE o.stage_id = t.stage_id AND o.part_id = c.part_id)
    OR (c.part_id IS NULL AND EXISTS (SELECT 1 FROM open_units o
            WHERE o.stage_id = t.stage_id AND o.part_id IS NULL
              AND o.loose_episode = c.episode_id)))))
ORDER BY w.id, e.sort_key, e.id, p.sort_key, p.id, s.position, s.id,
         c.sort_key, c.id, t.id;''',
      [
        now,
        workId,
        if (includeDone) 1 else 0,
        if (includeHandedOff) 1 else 0,
        if (includeArchived) 1 else 0,
      ],
    );
    final sharedLabels = _sharedLabels();
    final cutStyle = settings.cutStyle;
    final episodeStyle = settings.episodeStyle;
    // Many rows share an episode, and a cut its stages: show each once.
    final shownCuts = <String, String>{};
    final shownEpisodes = <String, String>{};
    String? cut(Object? v) => v == null
        ? null
        : shownCuts.putIfAbsent(v as String, () => shownNumber(v, cutStyle));
    return [
      for (final r in rows)
        TaskRow(
          id: r['id'] as int,
          status: TaskStatus.fromDb(r['status'] as String),
          take: r['take'] as int,
          workId: r['work_id'] as int,
          workTitle: r['title'] as String,
          clientName: r['client_name'] as String?,
          clientColor: r['client_color'] as int?,
          currency: r['currency'] as String,
          episodeId: r['episode_id'] as int,
          episodeNumber: shownEpisodes.putIfAbsent(
            r['episode_number'] as String,
            () => shownNumber(r['episode_number'] as String, episodeStyle),
          ),
          stageId: r['stage_id'] as int,
          stageName: r['stage_name'] as String,
          stagePosition: r['stage_position'] as int,
          cutId: r['cut_id'] as int?,
          cutNumber: cut(r['cut_number']),
          lengthMs: r['length_ms'] as int?,
          storyboardId: r['storyboard_id'] as int?,
          storyboardLabel: r['storyboard_label'] as String?,
          partId: r['part_id'] as int?,
          partLabel: r['part_label'] as String?,
          plannedCutCount: r['planned_cut_count'] as int?,
          receivedAt: _utcOrNull(r['received_at']),
          ownDueAt: _utcOrNull(r['own_due']),
          partDueAt: _utcOrNull(r['part_due']),
          ownPlanStartAt: _utcOrNull(r['own_plan_start']),
          ownPlanEndAt: _utcOrNull(r['own_plan_end']),
          partPlanStartAt: _utcOrNull(r['part_plan_start']),
          partPlanEndAt: _utcOrNull(r['part_plan_end']),
          ownKickoffAt: _utcOrNull(r['own_kickoff']),
          sharedHeadCutId: r['shared_head'] as int?,
          sharedLabel: sharedLabels[r['shared_head']],
          partKickoffAt: _utcOrNull(r['part_kickoff']),
          pay: _pay(
            r['unit'] as String?,
            r['amount'] as int?,
            r['length_ms'] as int?,
            r['extra'] as int,
            _rounding(r['seconds_rounding'], rounding),
          ),
          worked: Duration(milliseconds: r['worked_ms'] as int),
          ownDueRevisions: r['own_revs'] as int,
          partDueRevisions: r['part_revs'] as int,
          ownFirstDueAt: _utcOrNull(r['own_first']),
          partFirstDueAt: _utcOrNull(r['part_first']),
          ownWaitState: r['wait_state'] as int?,
          ownWaitReason: r['wait_reason'] as String?,
          ownWaitUntil: _utcOrNull(r['wait_until']),
          partWaiting: r['part_waiting'] == 1,
          partWaitReason: r['part_wait_reason'] as String?,
          partWaitUntil: _utcOrNull(r['part_wait_until']),
          handedOffAt: _utcOrNull(r['handed_off_at']),
          handedOffNote: r['handed_off_note'] as String?,
          archived: r['archived'] == 1,
        ),
    ];
  }

  /// Schedule units — part × stage, part-less cuts of an episode × stage,
  /// or a storyboard task alone — with progress, status, pay and time,
  /// sorted by deadline (none last). Two queries in all, whatever the row
  /// count: the settings read and [taskRows].
  /// Finished units are left out unless [includeDone].
  List<PartGroup> partGroups({
    int? workId,
    bool includeDone = false,
    bool includeHandedOff = false,
    bool includeArchived = false,
  }) => groupRows(
    taskRows(
      workId: workId,
      includeDone: includeDone,
      includeHandedOff: includeHandedOff,
      includeArchived: includeArchived,
    ),
    manualOrder: {
      for (final r in db.select('SELECT group_key, position FROM group_order;'))
        r['group_key'] as String: r['position'] as int,
    },
  );

  /// The calendar: every open unit as a bar over [basis] dates, laid out
  /// on the parallel-lanes setting. Units missing either end are not
  /// placed and are listed in `unplaced` (group keys).
  ({LaneLayout layout, List<String> unplaced}) calendarLayout({
    CalendarBasis basis = CalendarBasis.work,
  }) => _layout(partGroups(), basis);

  ({LaneLayout layout, List<String> unplaced}) _layout(
    List<PartGroup> groups,
    CalendarBasis basis,
  ) {
    final spans = <Span>[];
    final unplaced = <String>[];
    for (final g in groups) {
      if (!g.status.isOpen) continue;
      final (start, end) = switch (basis) {
        CalendarBasis.production => (g.kickoffAt, g.dueAt),
        CalendarBasis.work => (
          g.planStartAt ?? g.kickoffAt,
          g.planEndAt ?? g.dueAt,
        ),
      };
      if (start == null || end == null || end.isBefore(start)) {
        unplaced.add(g.key);
      } else {
        spans.add(Span(g.key, start, end));
      }
    }
    return (
      layout: layoutLanes(
        spans,
        settings.parallelLanes,
        pinned: {
          for (final r in db.select('SELECT group_key, lane FROM lane_pins;'))
            r['group_key'] as String: r['lane'] as int,
        },
      ),
      unplaced: unplaced,
    );
  }

  /// Keeps everything where it is now (유저 2026-11-28: lines and row order
  /// change only when the user moves something or asks to sort): every
  /// calendar bar not pinned yet is pinned to the lane it shows on, and
  /// every unit without a saved place in the row order is added after the
  /// saved ones, in the order shown. Runs by itself before any date
  /// changes, so an edited bar or row stays put; new units find a free lane
  /// (or the end of the list) the first time they show, and are held from
  /// then on. [clearLanePins] and [clearGroupOrder] — the 「자동 정렬」
  /// buttons — let everything be placed afresh.
  void holdPlaces() => _transaction(() {
    final groups = partGroups();
    final layout = _layout(groups, CalendarBasis.work).layout;
    for (final MapEntry(key: key, value: lane) in layout.laneOf.entries) {
      if (layout.pinned.contains(key)) continue;
      db.execute(
        'INSERT OR IGNORE INTO lane_pins (group_key, lane) VALUES (?, ?);',
        [key, lane],
      );
    }
    final listed = {
      for (final r in db.select('SELECT group_key FROM group_order;'))
        r['group_key'] as String,
    };
    var next =
        db
                .select(
                  'SELECT COALESCE(MAX(position) + 1, 0) AS n FROM group_order;',
                )
                .first['n']
            as int;
    for (final g in groups) {
      if (listed.contains(g.key)) continue;
      db.execute(
        'INSERT INTO group_order (group_key, position) VALUES (?, ?);',
        [g.key, next++],
      );
    }
  });

  /// Pins a calendar bar (by group key) to [lane], as after a drag
  /// between lanes. The layout keeps it there unless it overlaps another
  /// pinned bar or the lane is past the lane count — then it overflows.
  void pinLane(String groupKey, int lane) => db.execute(
    'INSERT INTO lane_pins (group_key, lane) VALUES (?, ?) '
    'ON CONFLICT (group_key) DO UPDATE SET lane = excluded.lane;',
    [groupKey, lane],
  );

  /// Lets one bar be placed automatically again.
  void unpinLane(String groupKey) =>
      db.execute('DELETE FROM lane_pins WHERE group_key = ?;', [groupKey]);

  /// Lets every bar be placed automatically again.
  void clearLanePins() => db.execute('DELETE FROM lane_pins;');

  // ---- lines (the work tab's lanes) ----
  // The lane count and names live in the settings (parallel_lanes,
  // lane_names); these keep them, and the pins, in step.

  /// The lanes in order: their names, null for an unnamed one.
  List<String?> lanes() => settings.laneNames;

  /// Adds a lane at the end; answers its index.
  int addLane({String? name}) => _transaction(() {
    final names = [...settings.laneNames, _blank(name)];
    settings
      ..parallelLanes = names.length
      ..laneNames = names;
    return names.length - 1;
  });

  /// Removes lane [index]: bars pinned to it are let go, bars pinned to
  /// later lanes move down one. The last lane cannot go.
  void removeLane(int index) => _transaction(() {
    final names = settings.laneNames;
    RangeError.checkValidIndex(index, names, 'index');
    if (names.length == 1) throw StateError('The last lane cannot go.');
    db
      ..execute('DELETE FROM lane_pins WHERE lane = ?;', [index])
      ..execute('UPDATE lane_pins SET lane = lane - 1 WHERE lane > ?;', [
        index,
      ]);
    names.removeAt(index);
    settings
      ..parallelLanes = names.length
      ..laneNames = names;
  });

  /// Names lane [index]; null or blank leaves it unnamed.
  void renameLane(int index, String? name) {
    final names = settings.laneNames;
    RangeError.checkValidIndex(index, names, 'index');
    names[index] = _blank(name);
    settings.laneNames = names;
  }

  /// Saves the user's drag order: [groupKeys] (from [PartGroup.key]) in
  /// display order, replacing any earlier order. Units not listed fall
  /// after the listed ones, by deadline.
  void setGroupOrder(List<String> groupKeys) => _transaction(() {
    db.execute('DELETE FROM group_order;');
    for (var i = 0; i < groupKeys.length; i++) {
      db.execute(
        'INSERT OR IGNORE INTO group_order (group_key, position) VALUES (?, ?);',
        [groupKeys[i], i],
      );
    }
  });

  /// "Sort automatically": drops the drag order, back to deadline order.
  void clearGroupOrder() => db.execute('DELETE FROM group_order;');

  /// True when a drag order is saved.
  bool get hasGroupOrder =>
      db.select('SELECT 1 FROM group_order LIMIT 1;').isNotEmpty;

  /// The pace (cuts per working day) for [group] as of now, using the
  /// day start, rest weekdays and pace-end settings.
  Pace? paceOf(PartGroup group) => paceFor(
    group,
    clock(),
    dayStartMinutes: settings.dayStartMinutes,
    restWeekdays: settings.restWeekdays,
    daysOff: _daysOff(),
    isHoliday: restHoliday(),
    endAt: settings.paceEnd,
  );

  /// The public-holiday test when the user rests on holidays, else null.
  bool Function(DateTime)? restHoliday() =>
      settings.restOnHolidays ? holidayTest(settings.holidayCountry) : null;

  /// [settings.holidayCountry]'s holidays on the local days from [from] up
  /// to (not including) [to] — for showing them; empty for none.
  List<Holiday> holidays({required DateTime from, required DateTime to}) {
    final start = DateTime.utc(from.year, from.month, from.day);
    final end = DateTime.utc(to.year, to.month, to.day);
    final country = settings.holidayCountry;
    return [
      for (var y = start.year; y <= end.year; y++)
        for (final h in holidaysOf(country, y))
          if (!h.date.isBefore(start) && h.date.isBefore(end)) h,
    ];
  }

  /// The usual pace per stage name: cuts handed over (submitted) in the
  /// last [days] days up to today, divided
  /// by the working days in that window. Stages of every work with the
  /// same name pool together ("LO" in two works is one LO speed).
  List<UsualPace> usualPaces({int? days}) {
    days ??= settings.recentPaceDays;
    final now = clock();
    final today = dayRange(now, settings.dayStartMinutes);
    final from = DateTime(
      today.start.year,
      today.start.month,
      today.start.day - (days - 1),
    ).add(Duration(minutes: settings.dayStartMinutes));
    final workDays = workDaysBetween(
      from,
      today.start,
      restWeekdays: settings.restWeekdays,
      daysOff: _daysOff(from: from),
      isHoliday: restHoliday(),
    );
    return [
      for (final r in db.select(
        '''
SELECT s.name AS stage_name, COUNT(DISTINCT ${_unitKeySql('t', 'c')}) AS cuts
FROM live_tasks t JOIN work_stages s ON s.id = t.stage_id
LEFT JOIN cuts c ON c.id = t.cut_id
WHERE t.handed_off_at IS NULL
  AND t.submitted_at >= ?
  AND t.submitted_at < ?
GROUP BY s.name ORDER BY s.name;''',
        [_ms(from), _ms(today.end)],
      ))
        UsualPace(
          stageName: r['stage_name'] as String,
          cuts: r['cuts'] as int,
          workDays: workDays,
        ),
    ];
  }

  /// Each stage name's recent average (the last
  /// [SettingsStore.recentPaceDays] days) and overall average (from its
  /// first handed-over cut to today), both in cuts per working day.
  List<StagePace> stagePaces() {
    final recent = {for (final u in usualPaces()) u.stageName: u};
    final now = clock();
    final today = dayRange(now, settings.dayStartMinutes);
    final rest = settings.restWeekdays;
    final off = _daysOff();
    final holiday = restHoliday();
    final overall = <String, UsualPace>{};
    for (final r in db.select(
      '''
SELECT s.name AS stage_name, COUNT(DISTINCT ${_unitKeySql('t', 'c')}) AS cuts,
       MIN(t.submitted_at) AS first_at
FROM live_tasks t JOIN work_stages s ON s.id = t.stage_id
LEFT JOIN cuts c ON c.id = t.cut_id
WHERE t.handed_off_at IS NULL
  AND t.submitted_at IS NOT NULL
  AND t.submitted_at < ?
GROUP BY s.name;''',
      [_ms(today.end)],
    )) {
      final first = dayRange(
        _utc(r['first_at'] as int),
        settings.dayStartMinutes,
      ).start;
      final name = r['stage_name'] as String;
      overall[name] = UsualPace(
        stageName: name,
        cuts: r['cuts'] as int,
        workDays: workDaysBetween(
          first,
          today.start,
          restWeekdays: rest,
          daysOff: off,
          isHoliday: holiday,
        ),
      );
    }
    return [
      for (final name in {...overall.keys, ...recent.keys}.toList()..sort())
        StagePace(
          stageName: name,
          recent:
              recent[name] ??
              UsualPace(
                stageName: name,
                cuts: 0,
                workDays: recent.values.firstOrNull?.workDays ?? 0,
              ),
          overall:
              overall[name] ?? UsualPace(stageName: name, cuts: 0, workDays: 0),
        ),
    ];
  }

  /// Recent cuts per working day by stage name (null without working
  /// days), the speed the plan signal compares against.
  Map<String, double?> recentPerDay() => {
    for (final u in usualPaces()) u.stageName: u.perDay,
  };

  /// The deadline and plan signals and needed pace of every group in
  /// [partGroups], by group key.
  Map<String, GroupSignals> signals({bool includeDone = false}) =>
      _signalsOf(partGroups(includeDone: includeDone), clock());

  /// [_signals] for each of [groups] as of [now], by group key.
  Map<String, GroupSignals> _signalsOf(List<PartGroup> groups, DateTime now) {
    final dayStart = settings.dayStartMinutes;
    final rest = settings.restWeekdays;
    final off = _daysOff(from: now);
    final holiday = restHoliday();
    final paceEnd = settings.paceEnd;
    final recent = recentPerDay();
    return {
      for (final g in groups)
        g.key: _signals(g, now, dayStart, rest, off, holiday, paceEnd, recent),
    };
  }

  static GroupSignals _signals(
    PartGroup g,
    DateTime now,
    int dayStart,
    Set<int> rest,
    List<DaysOff> off,
    bool Function(DateTime)? holiday,
    PaceEnd paceEnd,
    Map<String, double?> recent,
  ) {
    final pace = paceFor(
      g,
      now,
      dayStartMinutes: dayStart,
      restWeekdays: rest,
      daysOff: off,
      isHoliday: holiday,
      endAt: paceEnd,
    );
    return GroupSignals(
      due: dueSignal(g, now: now, dayStartMinutes: dayStart),
      plan: planSignal(
        g,
        now: now,
        dayStartMinutes: dayStart,
        pace: pace,
        recentPerDay: recent[g.stageName],
      ),
      pace: pace,
    );
  }

  /// Days off from [start] to [end] (one day when null): one rest event
  /// per local day, all named [title] (empty: the view's own word).
  /// Answers their ids.
  List<int> addRestDays(DateTime start, {DateTime? end, String title = ''}) {
    final r = DaysOff(start, end);
    return _transaction(
      () => [
        for (
          var d = r.start;
          !d.isAfter(r.end);
          d = d.add(const Duration(days: 1))
        )
          addEvent(date: d, title: title, rest: true),
      ],
    );
  }

  /// The days off (rest events, earliest first), from [from] on when given.
  List<EventRow> restDays({DateTime? from}) => [
    for (final r in db.select(
      'SELECT id, day, title, note FROM events '
      'WHERE rest = 1 AND episode_id IS NULL AND (? IS NULL OR day >= ?) '
      'ORDER BY day, id;',
      [
        if (from == null) null else _isoDate(from),
        if (from == null) null else _isoDate(from),
      ],
    ))
      (
        id: r['id'] as int,
        episodeId: null,
        card: null,
        date: DateTime.parse(r['day'] as String),
        timeMinutes: null,
        title: r['title'] as String,
        note: r['note'] as String?,
        rest: true,
      ),
  ];

  /// [restDays] as the day-off ranges the pace counts with.
  List<DaysOff> _daysOff({DateTime? from}) => [
    for (final e in restDays(from: from)) DaysOff(e.date),
  ];

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The "today" list: open groups that are due within [horizonDays] days
  /// (or late), in progress or in retake, or whose planned start has come.
  /// Nothing is hidden for a later planned start — such entries carry
  /// `beforePlan` so the view can dim them ("starts 12/7").
  /// Sorted by days left (no deadline last), then urgency.
  /// Each entry carries its [Pace]. `late` counts late open groups plus
  /// late open cuts whose own deadline overrides their part's.
  /// `cutsToday` sums what every open group asks of today — not only the
  /// listed ones — so overlapping parts add up.
  TodayView today({int horizonDays = 4}) {
    final now = clock();
    final groups = partGroups();
    return _todayOf(groups, _signalsOf(groups, now), now, horizonDays);
  }

  /// [today] over [groups] with their [signals] as of [now].
  TodayView _todayOf(
    List<PartGroup> groups,
    Map<String, GroupSignals> signals,
    DateTime now,
    int horizonDays,
  ) {
    final dayStart = settings.dayStartMinutes;
    int? left(DateTime? due) =>
        due == null ? null : dueInDays(due, now, dayStart);

    var late = 0;
    var cutsToday = 0.0;
    final entries = <TodayEntry>[];
    for (final g in groups) {
      final status = g.status;
      final days = left(g.dueAt);
      if (status.isOpen && days != null && days < 0) late++;
      for (final t in g.tasks) {
        if (t.dueOverridden && t.isOpen) {
          final d = left(t.ownDueAt);
          if (d != null && d < 0) late++;
        }
      }
      final sig = signals[g.key]!;
      final pace = sig.pace;
      if (pace != null) cutsToday += pace.today;
      final due = days != null && days <= horizonDays;
      final active =
          status == TaskStatus.inProgress || status == TaskStatus.retake;
      final toStart = left(g.planStartAt);
      final planStarted = toStart != null && toStart <= 0;
      final beforePlan = toStart != null && toStart > 0;
      if (status.isOpen && (due || active || planStarted)) {
        entries.add(
          TodayEntry(
            group: g,
            dueInDays: days,
            pace: pace,
            beforePlan: beforePlan,
            planStarted: planStarted,
            due: sig.due,
            plan: sig.plan,
          ),
        );
      }
    }
    entries.sort((a, b) {
      final da = a.dueInDays;
      final dbb = b.dueInDays;
      if (da != dbb) {
        if (da == null) return 1;
        if (dbb == null) return -1;
        return da.compareTo(dbb);
      }
      return a.group.status.urgency.compareTo(b.group.status.urgency);
    });
    return TodayView(entries: entries, late: late, cutsToday: cutsToday);
  }

  /// The dashboard tab (유저 2026-11-28) in one read: the [today] list,
  /// today and this week as [stats] ranges (the week start setting), the
  /// open cards due within [dueWithinDays] days or late (at most
  /// [dueLimit], soonest first, each with its [signals] pace), events
  /// ([events], [cardEvents]) and [holidays] of today and tomorrow,
  /// retakes and [holding]'s waiting count.
  Dashboard dashboard({
    int horizonDays = 4,
    int dueWithinDays = 7,
    int dueLimit = 8,
  }) {
    final now = clock();
    final dayStart = settings.dayStartMinutes;
    final start = dayRange(now, dayStart).start;
    final day = DateTime(start.year, start.month, start.day);
    DateTime plus(int days) => DateTime(day.year, day.month, day.day + days);

    final groups = partGroups();
    final signals = _signalsOf(groups, now);
    final today = _todayOf(groups, signals, now, horizonDays);

    final dueSoon = <DashboardDue>[];
    final retakeCards = <String>[];
    final retakeUnits = <String>{};
    for (final g in groups) {
      if (!g.status.isOpen) continue;
      final due = g.dueAt;
      final days = due == null ? null : dueInDays(due, now, dayStart);
      if (days != null && days <= dueWithinDays) {
        dueSoon.add(
          DashboardDue(group: g, daysLeft: days, pace: signals[g.key]?.pace),
        );
      }
      final retakes = [
        for (final t in g.tasks)
          if (t.status == TaskStatus.retake) t.unitKey,
      ];
      if (retakes.isNotEmpty) {
        retakeCards.add(g.key);
        retakeUnits.addAll(retakes);
      }
    }
    dueSoon.sort((a, b) {
      final d = a.daysLeft.compareTo(b.daysLeft);
      return d != 0 ? d : b.remaining.compareTo(a.remaining);
    });

    final events = [
      ...this.events(from: day, to: plus(2)).values.expand((e) => e),
      ...cardEvents(from: day, to: plus(2)).values.expand((e) => e),
    ]..sort(_byWhen);

    // One read of the statistics facts for the three ranges.
    final facts = _statsFacts(null, null);
    final weekFrom = plus(-((day.weekday - settings.weekStart) % 7));
    DateTime weekPlus(int days) =>
        DateTime(weekFrom.year, weekFrom.month, weekFrom.day + days);
    StatsSlice range(DateTime from, DateTime to) =>
        _stats(facts, from, to, StatsBucket.week, filtered: false).total;

    return Dashboard(
      day: day,
      today: today,
      todayStats: range(day, plus(1)),
      running: runningTimer(),
      timerTarget: timerTarget(),
      dueSoon: dueSoon.take(dueLimit).toList(),
      events: events,
      holidays: holidays(from: day, to: plus(2)),
      retakeCuts: retakeUnits.length,
      retakeCards: retakeCards,
      waiting: holding().waiting,
      thisWeek: range(weekFrom, weekPlus(7)),
      lastWeek: range(weekPlus(-7), weekFrom),
      weekFrom: weekFrom,
    );
  }

  /// Events by day, all-day first, then time, then id — as [events] lists.
  static int _byWhen(EventRow a, EventRow b) {
    final d = a.date.compareTo(b.date);
    if (d != 0) return d;
    final ta = a.timeMinutes ?? -1;
    final tb = b.timeMinutes ?? -1;
    return ta != tb ? ta.compareTo(tb) : a.id.compareTo(b.id);
  }

  static SecondsRounding _rounding(Object? work, SecondsRounding app) =>
      work == null ? app : SecondsRounding.fromDb(work as String);

  /// Sets or clears one task's own production deadline (a cut's override
  /// of its part's).
  ///
  /// Like [setPartDue]: corrects the revision in force; null removes the
  /// task's own deadline, every revision.
  void setTaskDue(int taskId, DateTime? dueAt) => _transaction(() {
    _holdBeforeDates();
    final target = DueTarget.task(taskId);
    if (dueAt == null) {
      _deleteRevisions(target);
      _syncDue(target);
    } else {
      _setCurrentDue(target, dueAt);
    }
  });

  /// Sets or clears (null) when production work began for a part × stage.
  void setPartKickoff(int partId, int stageId, DateTime? kickoffAt) =>
      _transaction(() => _setPartKickoff(partId, stageId, kickoffAt));

  void _setPartKickoff(int partId, int stageId, DateTime? kickoffAt) {
    _holdBeforeDates();
    if (kickoffAt == null) {
      db.execute(
        'DELETE FROM part_stage_kickoffs WHERE part_id = ? AND stage_id = ?;',
        [partId, stageId],
      );
      return;
    }
    db.execute(
      'INSERT INTO part_stage_kickoffs (part_id, stage_id, kickoff_at) '
      'VALUES (?, ?, ?) ON CONFLICT (part_id, stage_id) '
      'DO UPDATE SET kickoff_at = excluded.kickoff_at;',
      [partId, stageId, _ms(kickoffAt)],
    );
  }

  /// Sets or clears one task's own kickoff (a cut's override).
  void setTaskKickoff(int taskId, DateTime? kickoffAt) => _transaction(() {
    _holdBeforeDates();
    db.execute('UPDATE tasks SET kickoff_at = ? WHERE id = ?;', [
      _ms(kickoffAt),
      taskId,
    ]);
  });

  /// Writes a part × stage's production schedule — kickoff and deadline —
  /// in one transaction, as a timeline bar dropped after a drag. A null
  /// clears that end.
  void setPartSchedule(
    int partId,
    int stageId, {
    required DateTime? kickoffAt,
    required DateTime? dueAt,
  }) => _transaction(() {
    if (kickoffAt != null && dueAt != null && dueAt.isBefore(kickoffAt)) {
      throw ArgumentError('A deadline cannot come before the kickoff.');
    }
    setPartKickoff(partId, stageId, kickoffAt);
    if (dueAt == null) {
      clearPartDue(partId, stageId);
    } else {
      setPartDue(partId, stageId, dueAt);
    }
  });

  /// Sets the user's own plan for a part × stage. Both null removes it.
  void setPartPlan(int partId, int stageId, {DateTime? start, DateTime? end}) =>
      _transaction(() => _setPartPlan(partId, stageId, start, end));

  void _setPartPlan(int partId, int stageId, DateTime? start, DateTime? end) {
    _holdBeforeDates();
    if (start == null && end == null) {
      db.execute(
        'DELETE FROM part_stage_plans WHERE part_id = ? AND stage_id = ?;',
        [partId, stageId],
      );
      return;
    }
    db.execute(
      'INSERT INTO part_stage_plans (part_id, stage_id, start_at, end_at) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (part_id, stage_id) '
      'DO UPDATE SET start_at = excluded.start_at, end_at = excluded.end_at;',
      [partId, stageId, _ms(start), _ms(end)],
    );
  }

  /// Sets one task's own plan; a null end follows the part's.
  void setTaskPlan(int taskId, {DateTime? start, DateTime? end}) {
    if (start != null && end != null && end.isBefore(start)) {
      throw ArgumentError('A plan cannot end before it starts.');
    }
    _transaction(() {
      _holdBeforeDates();
      db.execute(
        'UPDATE tasks SET plan_start_at = ?, plan_end_at = ? WHERE id = ?;',
        [_ms(start), _ms(end), taskId],
      );
    });
  }

  /// The rate unit preselected when entering this work's rates.
  RateUnit workDefaultRateUnit(int workId) => RateUnit.fromDb(
    db.select('SELECT default_rate_unit FROM works WHERE id = ?;', [
          workId,
        ]).first['default_rate_unit']
        as String,
  );

  void setWorkDefaultRateUnit(int workId, RateUnit unit) => db.execute(
    'UPDATE works SET default_rate_unit = ? WHERE id = ?;',
    [unit.dbName, workId],
  );

  static int? _ms(DateTime? t) => t?.toUtc().millisecondsSinceEpoch;

  /// Gives one task (one stage of one cut) its own rate; null goes back to
  /// the episode's rate for the stage.
  void setTaskRate(int taskId, Rate? rate) => db.execute(
    'UPDATE tasks SET rate_unit = ?, rate_amount = ? WHERE id = ?;',
    [rate?.unit.dbName, rate?.amount, taskId],
  );

  /// Sets the work's own seconds rounding; null follows the app setting.
  void setWorkRounding(int workId, SecondsRounding? rounding) => db.execute(
    'UPDATE works SET seconds_rounding = ? WHERE id = ?;',
    [rounding?.dbName, workId],
  );

  /// Moves every task in [taskIds] to [status] in one transaction, with
  /// the same timestamps a single [setStatus] would set.
  void setStatusMany(Iterable<int> taskIds, TaskStatus status) =>
      _transaction(() {
        for (final id in taskIds) {
          setStatus(id, status);
        }
      });

  /// Stage presets as (id, name, isDefault), default first, then by name.
  List<({int id, String name, bool isDefault})> presets() => [
    for (final r in db.select(
      'SELECT id, name, is_default FROM stage_presets '
      'ORDER BY is_default DESC, name, id;',
    ))
      (
        id: r['id'] as int,
        name: r['name'] as String,
        isDefault: r['is_default'] == 1,
      ),
  ];

  /// Adds a preset with [stages] in order, and returns its id.
  int createPreset(String name, List<String> stages) => _transaction(() {
    db.execute('INSERT INTO stage_presets (name) VALUES (?);', [name]);
    final id = db.lastInsertRowId;
    setPresetStages(id, stages);
    return id;
  });

  void renamePreset(int presetId, String name) => db.execute(
    'UPDATE stage_presets SET name = ? WHERE id = ?;',
    [name, presetId],
  );

  /// Makes [presetId] the one preset new works use when none is chosen.
  void setDefaultPreset(int presetId) => _transaction(() {
    db
      ..execute('UPDATE stage_presets SET is_default = 0 WHERE is_default = 1;')
      ..execute('UPDATE stage_presets SET is_default = 1 WHERE id = ?;', [
        presetId,
      ]);
    if (db.updatedRows != 1) {
      throw ArgumentError.value(presetId, 'presetId', 'no such preset');
    }
  });

  /// Deletes a preset. Works made from it keep their stages. The default
  /// preset cannot be deleted; make another the default first.
  void deletePreset(int presetId) => _transaction(() {
    final rows = db.select(
      'SELECT is_default FROM stage_presets WHERE id = ?;',
      [presetId],
    );
    if (rows.isEmpty) return;
    if (rows.first['is_default'] == 1) {
      throw StateError('The default stage preset cannot be deleted.');
    }
    db
      ..execute('DELETE FROM stage_preset_items WHERE preset_id = ?;', [
        presetId,
      ])
      ..execute('DELETE FROM stage_presets WHERE id = ?;', [presetId]);
  });

  static int? _pay(
    String? unit,
    int? amount,
    int? lengthMs,
    int extra,
    SecondsRounding rounding,
  ) {
    if (unit == null || amount == null) return null;
    final base = Rate(
      RateUnit.fromDb(unit),
      amount,
    ).payFor(lengthMs: lengthMs, rounding: rounding);
    return base == null ? null : base + extra;
  }

  int _now() => clock().toUtc().millisecondsSinceEpoch;

  T _transaction<T>(T Function() body) {
    db.execute('SAVEPOINT catalogue;');
    _depth++;
    try {
      final result = body();
      db.execute('RELEASE catalogue;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK TO catalogue;');
      db.execute('RELEASE catalogue;');
      rethrow;
    } finally {
      if (--_depth == 0) _placesHeld = false;
    }
  }

  int _depth = 0;
  bool _placesHeld = false;

  /// Before a date changes: [holdPlaces], once per outermost transaction —
  /// unless everything is held already ([_placesHeldAlready]).
  void _holdBeforeDates() {
    if (_placesHeld) return;
    _placesHeld = true;
    if (!placesHeld) holdPlaces();
  }

  /// Whether everything is held already ([holdPlaces] would change
  /// nothing that shows): see [_placesHeldAlready].
  bool get placesHeld => _placesHeldAlready();

  /// The cheap check that lets most date writes skip [holdPlaces]: every
  /// open unit has a place in the row order, and every open unit that
  /// could be on the calendar (some start and some end, at any level — a
  /// superset of the bars actually placed, so a miss only costs time) is
  /// pinned. One grouped query instead of the whole layout. The keys are
  /// [TaskRow.groupKey]'s, written in SQL; a test holds the two together.
  bool _placesHeldAlready() =>
      db.select('''
WITH units AS (
  SELECT CASE WHEN t.storyboard_id IS NOT NULL THEN 'storyboard:' || t.id
              WHEN c.part_id IS NULL
                THEN 'nopart:' || c.episode_id || ':' || t.stage_id
              ELSE 'part:' || c.part_id || ':' || t.stage_id END AS key,
         MAX(t.kickoff_at IS NOT NULL OR t.plan_start_at IS NOT NULL
             OR k.kickoff_at IS NOT NULL OR pl.start_at IS NOT NULL)
           AND MAX(t.due_at IS NOT NULL OR t.plan_end_at IS NOT NULL
             OR d.due_at IS NOT NULL OR pl.end_at IS NOT NULL) AS dated
  FROM live_tasks t
  LEFT JOIN cuts c ON c.id = t.cut_id
  LEFT JOIN part_stage_dues d
    ON d.part_id = c.part_id AND d.stage_id = t.stage_id
  LEFT JOIN part_stage_kickoffs k
    ON k.part_id = c.part_id AND k.stage_id = t.stage_id
  LEFT JOIN part_stage_plans pl
    ON pl.part_id = c.part_id AND pl.stage_id = t.stage_id
  WHERE t.handed_off_at IS NULL AND t.status <> 'submitted'
  GROUP BY key
)
SELECT NOT EXISTS (
  SELECT 1 FROM units u
  WHERE NOT EXISTS (SELECT 1 FROM group_order o WHERE o.group_key = u.key)
     OR (u.dated AND NOT EXISTS (
           SELECT 1 FROM lane_pins l WHERE l.group_key = u.key))
) AS held;''').first['held'] ==
      1;
}

/// What deleting a set of tasks takes away: the tasks that exist, and the
/// cuts, storyboards, parts, episodes and works left empty by them — each
/// a JSON id list, for `json_each`. One reading serves both
/// [CatalogueStore.deletionSummary] and [CatalogueStore.deleteTasks], so
/// the confirmation counts what the deletion does.
class _DeletionPlan {
  _DeletionPlan._(
    this.tasks,
    this.cuts,
    this.storyboards,
    this.parts,
    this.episodes,
    this.works,
  );

  factory _DeletionPlan.of(CommonDatabase db, String ids) {
    String list(String select, List<Object?> args) =>
        db
                .select(
                  "SELECT COALESCE(json_group_array(id), '[]') AS ids "
                  'FROM ($select);',
                  args,
                )
                .first['ids']
            as String;
    const inList1 = 'IN (SELECT value FROM json_each(?1))';
    const inList2 = 'IN (SELECT value FROM json_each(?2))';
    final tasks = list('SELECT id FROM tasks WHERE id $inList1', [ids]);
    final cuts = list(
      'SELECT c.id FROM cuts c '
      'WHERE c.id IN (SELECT cut_id FROM tasks WHERE id $inList1) '
      'AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.cut_id = c.id '
      'AND t.id NOT $inList1)',
      [tasks],
    );
    final storyboards = list(
      'SELECT sb.id FROM storyboards sb '
      'WHERE sb.id IN (SELECT storyboard_id FROM tasks WHERE id $inList1) '
      'AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.storyboard_id = sb.id '
      'AND t.id NOT $inList1)',
      [tasks],
    );
    final parts = list(
      'SELECT p.id FROM parts p '
      'WHERE p.id IN (SELECT part_id FROM cuts WHERE id $inList1) '
      'AND NOT EXISTS (SELECT 1 FROM cuts c WHERE c.part_id = p.id '
      'AND c.id NOT $inList1)',
      [cuts],
    );
    final episodes = list(
      'SELECT e.id FROM episodes e '
      'WHERE e.id IN (SELECT episode_id FROM cuts WHERE id $inList1 '
      'UNION SELECT episode_id FROM storyboards WHERE id $inList2) '
      'AND NOT EXISTS (SELECT 1 FROM cuts c WHERE c.episode_id = e.id '
      'AND c.id NOT $inList1) '
      'AND NOT EXISTS (SELECT 1 FROM storyboards sb '
      'WHERE sb.episode_id = e.id AND sb.id NOT $inList2)',
      [cuts, storyboards],
    );
    final works = list(
      'SELECT w.id FROM works w '
      'WHERE w.id IN (SELECT work_id FROM episodes WHERE id $inList1) '
      'AND NOT EXISTS (SELECT 1 FROM episodes e WHERE e.work_id = w.id '
      'AND e.id NOT $inList1)',
      [episodes],
    );
    return _DeletionPlan._(tasks, cuts, storyboards, parts, episodes, works);
  }

  final String tasks;
  final String cuts;
  final String storyboards;
  final String parts;
  final String episodes;
  final String works;

  static List<int> _ids(String json) => [
    for (final s in json.substring(1, json.length - 1).split(','))
      if (s.isNotEmpty) int.parse(s),
  ];

  Set<int> get taskIds => _ids(tasks).toSet();
  int get cutCount => _ids(cuts).length;
  List<int> get partIds => _ids(parts);
  List<int> get episodeIds => _ids(episodes);
  List<int> get workIds => _ids(works);
}
