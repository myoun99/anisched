import 'dart:convert';

import 'package:sqlite3/common.dart';

/// One forward-only schema step. [version] is the `user_version` the
/// database has after [apply] runs.
class Migration {
  const Migration(this.version, this.apply);

  final int version;
  final void Function(CommonDatabase db) apply;
}

/// Every migration, oldest first. Append only — never edit a shipped step;
/// a fix is a new step. Versions must be 1, 2, 3, … with no gaps.
///
/// v1: timer intervals. v2: the work catalogue (clients, works, stages,
/// episodes, cuts, storyboards, rates, tasks, retakes). v3: parts with
/// per-stage deadlines, settings, and timer intervals linked to tasks.
/// v4: editable stage presets that new works copy. v5: a work's own
/// seconds rounding. v6: the user's own plan (start/end) beside the
/// production deadline, and a work's default rate unit. v7: days off.
/// v8: the live_tasks view (archiving hides everything beneath). v9: the
/// production kickoff date and the user's own order of schedule units.
/// v10: role presets, pinned calendar lanes, shared-cut links and a work's
/// cut-number format.
final List<Migration> migrations = [
  Migration(1, (db) {
    db.execute('''
CREATE TABLE work_intervals (
  id INTEGER PRIMARY KEY,
  started_at INTEGER NOT NULL,
  stopped_at INTEGER,
  CHECK (stopped_at IS NULL OR stopped_at >= started_at)
);''');
    db.execute(
      'CREATE INDEX work_intervals_started ON work_intervals(started_at);',
    );
  }),
  const Migration(2, _v2Catalogue),
  const Migration(3, _v3PartsAndSettings),
  const Migration(4, _v4StagePresets),
  const Migration(5, _v5WorkRounding),
  const Migration(6, _v6PlansAndDefaultUnit),
  const Migration(7, _v7DaysOff),
  const Migration(8, _v8LiveTasks),
  const Migration(9, _v9KickoffAndOrder),
  const Migration(10, _v10RolesPinsSharedCuts),
  const Migration(11, _v11SubmittedDue),
  const Migration(12, _v12DueRevisionsAndWaits),
  const Migration(13, _v13HandedOff),
  const Migration(14, _v14DoneBeforeSubmitted),
  const Migration(15, _v15NumberStylesAndRanks),
  const Migration(16, _v16NumbersAsValues),
];

/// 유저 2026-11-28: done and submitted swap roles. **done** = the work is
/// finished, still in hand; **submitted** = handed to production, out of
/// hand. Under the old meaning both 'submitted' and 'done' (checked OK)
/// had left the user's hands, so both become 'submitted'; the work was
/// finished by the hand-in at the latest, so `done_at` becomes the first
/// hand-in.
///
/// Stage names become 「work/checker」 (Anicel's colour-label axes, 「수정」
/// dropped: 「LO 작감 수정」 → 「LO/작감」) in works, presets and roles; the
/// default preset gains 동화 · 동화/동검 · 시아게 · 시아게/셀검 · 리테이크 ·
/// 캐릭터디자인, and three single-stage roles join.
void _v14DoneBeforeSubmitted(CommonDatabase db) {
  db
    ..execute('''
UPDATE tasks SET status = 'submitted',
  submitted_at = COALESCE(submitted_at, done_at),
  done_at = COALESCE(submitted_at, done_at)
WHERE status IN ('submitted', 'done');''')
    ..execute('''
UPDATE tasks SET done_at = COALESCE(submitted_at, done_at)
WHERE status = 'retake' AND submitted_at IS NOT NULL;''');
  // Literal copies so this step never changes once shipped.
  const renames = {
    '콘티 체크': '콘티/감독',
    'LO 연출 수정': 'LO/연출',
    'LO 작감 수정': 'LO/작감',
    'LO 총작감 수정': 'LO/총작감',
    '원화 연출 수정': '원화/연출',
    '원화 작감 수정': '원화/작감',
    '원화 총작감 수정': '원화/총작감',
  };
  for (final MapEntry(key: old, value: now) in renames.entries) {
    db
      ..execute('UPDATE work_stages SET name = ? WHERE name = ?;', [now, old])
      ..execute('UPDATE stage_preset_items SET name = ? WHERE name = ?;', [
        now,
        old,
      ])
      ..execute('UPDATE role_stages SET stage_name = ? WHERE stage_name = ?;', [
        now,
        old,
      ]);
  }
  // Appended to the default preset where missing, so works already made
  // keep their stage lists; the user reorders the preset as they like.
  final preset = db.select(
    "SELECT id FROM stage_presets WHERE name = '기본' ORDER BY id LIMIT 1;",
  );
  if (preset.isNotEmpty) {
    final id = preset.first['id'] as int;
    const added = ['동화', '동화/동검', '시아게', '시아게/셀검', '리테이크', '캐릭터디자인'];
    for (final name in added) {
      db.execute(
        '''
INSERT INTO stage_preset_items (preset_id, name, position)
SELECT ?1, ?2, COALESCE(MAX(position), -1) + 1 FROM stage_preset_items
WHERE preset_id = ?1
  AND NOT EXISTS (SELECT 1 FROM stage_preset_items
                  WHERE preset_id = ?1 AND name = ?2);''',
        [id, name],
      );
    }
  }
  final start =
      db
              .select('SELECT COALESCE(MAX(position), -1) + 1 AS p FROM roles;')
              .first['p']
          as int;
  const roles = [
    ('동화', ['동화']),
    ('시아게', ['시아게']),
    ('캐릭터디자인', ['캐릭터디자인']),
  ];
  for (var i = 0; i < roles.length; i++) {
    db.execute('INSERT INTO roles (name, position) VALUES (?, ?);', [
      roles[i].$1,
      start + i,
    ]);
    final role = db.lastInsertRowId;
    for (var j = 0; j < roles[i].$2.length; j++) {
      db.execute(
        'INSERT INTO role_stages (role_id, stage_name, position) '
        'VALUES (?, ?, ?);',
        [role, roles[i].$2[j], j],
      );
    }
  }
}

/// 유저 2026-11-28: cut and episode numbers are written one way for the
/// whole document (settings `cut_style` · `episode_style`), so the
/// per-work cut format goes. The document keeps the format its works use
/// most (ties: the newest work's); none of them, or the default, writes
/// nothing. And more ranks from Anicel's checker axis.
void _v15NumberStylesAndRanks(CommonDatabase db) {
  final used = db.select('''
SELECT cut_prefix, cut_digits FROM works
GROUP BY cut_prefix, cut_digits
ORDER BY COUNT(*) DESC, MAX(id) DESC LIMIT 1;''');
  if (used.isNotEmpty) {
    final prefix = used.first['cut_prefix'] as String;
    final digits = used.first['cut_digits'] as int;
    if (prefix != 'C' || digits != 3) {
      db.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES ('cut_style', ?);",
        [
          jsonEncode({'prefix': prefix, 'digits': digits}),
        ],
      );
    }
  }
  db
    ..execute('ALTER TABLE works DROP COLUMN cut_prefix;')
    ..execute('ALTER TABLE works DROP COLUMN cut_digits;');

  // Seeded with a literal copy so this step never changes once shipped.
  final start =
      db
              .select('SELECT COALESCE(MAX(position) + 1, 0) AS p FROM roles;')
              .first['p']
          as int;
  const roles = [
    ('감독', ['콘티/감독']),
    ('총감독', ['콘티/총감독']),
    ('액션작감', ['LO/액션', '원화/액션']),
    ('동화검사', ['동화/동검']),
    ('셀검사', ['시아게/셀검']),
    ('러프원', ['러프원']),
  ];
  for (var i = 0; i < roles.length; i++) {
    db.execute('INSERT INTO roles (name, position) VALUES (?, ?);', [
      roles[i].$1,
      start + i,
    ]);
    final role = db.lastInsertRowId;
    for (var j = 0; j < roles[i].$2.length; j++) {
      db.execute(
        'INSERT INTO role_stages (role_id, stage_name, position) '
        'VALUES (?, ?, ?);',
        [role, roles[i].$2[j], j],
      );
    }
  }
}

/// 유저 2026-11-28: 「표기 = 표시만」. Cut and episode numbers are stored as
/// values — `C012A` → `12A`, `#07` → `7` — and shown in the document's
/// styles; names that are not numbers (`BANK1`, `SP`) stay as typed. The
/// prefix read off is the style's (any case) or none. Where two live
/// names become one value (`C1` and `C001` in one episode) both stay as
/// typed. And 감독 · 총감독 also check LO and 원화 (Anicel's checkers per
/// work allow it).
void _v16NumbersAsValues(CommonDatabase db) {
  String prefixOf(String key, String fallback) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?;', [key]);
    if (rows.isEmpty) return fallback;
    final m = jsonDecode(rows.first['value'] as String);
    return m is Map && m['prefix'] is String ? m['prefix'] as String : fallback;
  }

  // A literal copy of the rule, so this step never changes once shipped.
  final typedValue = RegExp(r'^0*(\d{1,9})([A-Za-z]*)$');
  String? valueOf(String typed, String prefix) {
    final t = typed.trim();
    final body =
        prefix.isNotEmpty &&
            t.length > prefix.length &&
            t.substring(0, prefix.length).toLowerCase() == prefix.toLowerCase()
        ? t.substring(prefix.length)
        : t;
    final m = typedValue.firstMatch(body);
    return m == null ? null : '${int.parse(m[1]!)}${m[2]!.toUpperCase()}';
  }

  String sortKey(String label) => label.trim().toLowerCase().replaceAllMapped(
    RegExp(r'\d+'),
    (m) => m[0]!.replaceFirst(RegExp('^0+(?=.)'), '').padLeft(10, '0'),
  );

  void convert(String table, String parent, String prefix) {
    final rows = db.select(
      'SELECT id, $parent AS p, number, archived_at IS NULL AS live '
      'FROM $table;',
    );
    // Values two live rows of one parent would share stay as typed.
    final liveCount = <(int, String), int>{};
    final values = <int, String?>{};
    for (final r in rows) {
      final v = valueOf(r['number'] as String, prefix);
      values[r['id'] as int] = v;
      if (v != null && r['live'] == 1) {
        final k = (r['p'] as int, v);
        liveCount[k] = (liveCount[k] ?? 0) + 1;
      }
    }
    for (final r in rows) {
      final v = values[r['id'] as int];
      if (v == null || v == r['number']) continue;
      if ((liveCount[(r['p'] as int, v)] ?? 0) > 1) continue;
      if (r['live'] != 1 && liveCount.containsKey((r['p'] as int, v))) {
        continue; // an archived twin of a live value keeps its name
      }
      db.execute('UPDATE $table SET number = ?, sort_key = ? WHERE id = ?;', [
        v,
        sortKey(v),
        r['id'],
      ]);
    }
  }

  convert('cuts', 'episode_id', prefixOf('cut_style', 'C'));
  convert('episodes', 'work_id', prefixOf('episode_style', '#'));

  for (final (role, stages) in const [
    ('감독', ['LO/감독', '원화/감독']),
    ('총감독', ['LO/총감독', '원화/총감독']),
  ]) {
    for (final r in db.select('SELECT id FROM roles WHERE name = ?;', [role])) {
      final id = r['id'] as int;
      var pos =
          db.select(
                'SELECT COALESCE(MAX(position) + 1, 0) AS p '
                'FROM role_stages WHERE role_id = ?;',
                [id],
              ).first['p']
              as int;
      for (final s in stages) {
        db.execute(
          'INSERT INTO role_stages (role_id, stage_name, position) '
          'SELECT ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM role_stages '
          'WHERE role_id = ? AND stage_name = ?);',
          [id, s, pos++, id, s],
        );
      }
    }
  }
}

/// A task taken off the user's hands (someone else does it now, 유저
/// 2026-11-28): out of the lists and the pace, still in the time
/// statistics. Not a delete.
void _v13HandedOff(CommonDatabase db) {
  db
    ..execute('ALTER TABLE tasks ADD COLUMN handed_off_at INTEGER;')
    ..execute('ALTER TABLE tasks ADD COLUMN handed_off_note TEXT;');
}

/// Deadlines in revisions (1st, 2nd … — a deadline extended after talking
/// it over) and the "waiting" flag (유저 2026-11-28).
///
/// `due_revisions` keeps every revision of a part × stage deadline or of a
/// task's own; the existing `part_stage_dues.due_at` / `tasks.due_at`
/// stay as the CURRENT (last) revision, kept in step by the store, so every
/// reader keeps working. Existing deadlines become revision 1.
///
/// Waiting: a part × stage row in `part_stage_waits` puts its cuts on hold;
/// a task's `wait_state` overrides it (1 waiting, 0 not, NULL follow).
void _v12DueRevisionsAndWaits(CommonDatabase db) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  for (final sql in [
    '''
CREATE TABLE due_revisions (
  id INTEGER PRIMARY KEY,
  part_id INTEGER REFERENCES parts(id),
  stage_id INTEGER REFERENCES work_stages(id),
  task_id INTEGER REFERENCES tasks(id),
  revision INTEGER NOT NULL CHECK (revision >= 1),
  due_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  CHECK ((task_id IS NULL AND part_id IS NOT NULL AND stage_id IS NOT NULL)
      OR (task_id IS NOT NULL AND part_id IS NULL AND stage_id IS NULL))
);''',
    'CREATE UNIQUE INDEX due_revisions_part ON due_revisions'
        '(part_id, stage_id, revision) WHERE task_id IS NULL;',
    'CREATE UNIQUE INDEX due_revisions_task ON due_revisions'
        '(task_id, revision) WHERE task_id IS NOT NULL;',
    'INSERT INTO due_revisions (part_id, stage_id, revision, due_at, '
        'created_at) SELECT part_id, stage_id, 1, due_at, $now '
        'FROM part_stage_dues;',
    'INSERT INTO due_revisions (task_id, revision, due_at, created_at) '
        'SELECT id, 1, due_at, COALESCE(received_at, $now) FROM tasks '
        'WHERE due_at IS NOT NULL;',
    '''
CREATE TABLE part_stage_waits (
  part_id INTEGER NOT NULL REFERENCES parts(id),
  stage_id INTEGER NOT NULL REFERENCES work_stages(id),
  reason TEXT,
  until_at INTEGER,
  since_at INTEGER NOT NULL,
  PRIMARY KEY (part_id, stage_id)
);''',
    'ALTER TABLE tasks ADD COLUMN wait_state INTEGER '
        'CHECK (wait_state IN (0, 1));',
    'ALTER TABLE tasks ADD COLUMN wait_reason TEXT;',
    'ALTER TABLE tasks ADD COLUMN wait_until INTEGER;',
    'ALTER TABLE tasks ADD COLUMN wait_since INTEGER;',
  ]) {
    db.execute(sql);
  }
}

/// The deadline in force when a task was first handed in, so deadline
/// adherence does not move when a deadline is edited later. Existing
/// hand-ins take today's deadline — the best record there is.
void _v11SubmittedDue(CommonDatabase db) {
  db
    ..execute('ALTER TABLE tasks ADD COLUMN submitted_due_at INTEGER;')
    ..execute('''
UPDATE tasks SET submitted_due_at =
  (SELECT due_at FROM task_dues WHERE task_id = tasks.id)
WHERE submitted_at IS NOT NULL;''');
}

/// Conventions: instants are UTC epoch milliseconds; money is an integer
/// in the currency's smallest unit; rows are soft-deleted via
/// `archived_at` because finished work must stay countable.
void _v2Catalogue(CommonDatabase db) {
  for (final sql in const [
    // closing_day NULL means the last day of the month.
    '''
CREATE TABLE clients (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  closing_day INTEGER CHECK (closing_day BETWEEN 1 AND 31),
  archived_at INTEGER
);''',
    '''
CREATE TABLE works (
  id INTEGER PRIMARY KEY,
  client_id INTEGER REFERENCES clients(id),
  title TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'JPY' CHECK (length(currency) = 3),
  created_at INTEGER NOT NULL,
  archived_at INTEGER
);''',
    // A work's own ordered, editable list of process stages.
    '''
CREATE TABLE work_stages (
  id INTEGER PRIMARY KEY,
  work_id INTEGER NOT NULL REFERENCES works(id),
  name TEXT NOT NULL,
  position INTEGER NOT NULL,
  archived_at INTEGER
);''',
    'CREATE INDEX work_stages_work ON work_stages(work_id, position);',
    '''
CREATE TABLE episodes (
  id INTEGER PRIMARY KEY,
  work_id INTEGER NOT NULL REFERENCES works(id),
  number TEXT NOT NULL,
  sort_key TEXT NOT NULL,
  title TEXT,
  archived_at INTEGER
);''',
    'CREATE INDEX episodes_work ON episodes(work_id, sort_key);',
    // length_ms: cut length, for per-second rates.
    '''
CREATE TABLE cuts (
  id INTEGER PRIMARY KEY,
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  number TEXT NOT NULL,
  sort_key TEXT NOT NULL,
  length_ms INTEGER CHECK (length_ms IS NULL OR length_ms >= 0),
  note TEXT,
  archived_at INTEGER
);''',
    'CREATE INDEX cuts_episode ON cuts(episode_id, sort_key);',
    '''
CREATE UNIQUE INDEX cuts_live_number ON cuts(episode_id, number)
  WHERE archived_at IS NULL;''',
    // The storyboard is one unit of work for an episode, not a cut.
    '''
CREATE TABLE storyboards (
  id INTEGER PRIMARY KEY,
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  label TEXT NOT NULL,
  archived_at INTEGER
);''',
    'CREATE INDEX storyboards_episode ON storyboards(episode_id);',
    // Default rate for a stage within an episode.
    '''
CREATE TABLE episode_rates (
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  stage_id INTEGER NOT NULL REFERENCES work_stages(id),
  unit TEXT NOT NULL CHECK (unit IN ('fixed', 'per_second')),
  amount INTEGER NOT NULL CHECK (amount >= 0),
  PRIMARY KEY (episode_id, stage_id)
);''',
    // One task = one stage of one cut or storyboard that is the user's.
    // rate_* override the episode rate when set.
    '''
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY,
  stage_id INTEGER NOT NULL REFERENCES work_stages(id),
  cut_id INTEGER REFERENCES cuts(id),
  storyboard_id INTEGER REFERENCES storyboards(id),
  status TEXT NOT NULL DEFAULT 'received' CHECK (status IN
    ('received', 'in_progress', 'submitted', 'retake', 'done')),
  received_at INTEGER,
  due_at INTEGER,
  submitted_at INTEGER,
  done_at INTEGER,
  rate_unit TEXT CHECK (rate_unit IN ('fixed', 'per_second')),
  rate_amount INTEGER CHECK (rate_amount >= 0),
  note TEXT,
  archived_at INTEGER,
  CHECK ((cut_id IS NULL) <> (storyboard_id IS NULL)),
  CHECK ((rate_unit IS NULL) = (rate_amount IS NULL))
);''',
    '''
CREATE UNIQUE INDEX tasks_live_cut ON tasks(stage_id, cut_id)
  WHERE cut_id IS NOT NULL AND archived_at IS NULL;''',
    '''
CREATE UNIQUE INDEX tasks_live_storyboard ON tasks(stage_id, storyboard_id)
  WHERE storyboard_id IS NOT NULL AND archived_at IS NULL;''',
    'CREATE INDEX tasks_due ON tasks(due_at) WHERE archived_at IS NULL;',
    'CREATE INDEX tasks_cut ON tasks(cut_id);',
    // take 2, 3, … without limit. Free unless marked paid.
    '''
CREATE TABLE retakes (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL REFERENCES tasks(id),
  take INTEGER NOT NULL CHECK (take >= 2),
  received_at INTEGER,
  due_at INTEGER,
  submitted_at INTEGER,
  paid INTEGER NOT NULL DEFAULT 0 CHECK (paid IN (0, 1)),
  amount INTEGER CHECK (amount >= 0),
  note TEXT,
  UNIQUE (task_id, take),
  CHECK (paid = 1 OR amount IS NULL)
);''',
  ]) {
    db.execute(sql);
  }
}

/// The schema version this build expects.
int get latestSchemaVersion => migrations.isEmpty ? 0 : migrations.last.version;

/// Thrown when the file was written by a newer build than this one.
class SchemaTooNewException implements Exception {
  SchemaTooNewException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'CommonDatabase schema v$found is newer than this build supports (v$supported).';
}

/// Brings [db] up to the latest version. Each step runs in its own
/// transaction together with its `user_version` bump, so a crash mid-way
/// leaves the file at the last completed version, never half-migrated.
void migrate(CommonDatabase db, {List<Migration>? steps}) {
  final all = steps ?? migrations;
  final target = all.isEmpty ? 0 : all.last.version;
  final current = db.userVersion;
  if (current > target) throw SchemaTooNewException(current, target);
  for (var i = 0; i < all.length; i++) {
    final step = all[i];
    if (step.version != i + 1) {
      throw StateError('Migration versions must be contiguous from 1.');
    }
    if (step.version <= current) continue;
    db.execute('BEGIN IMMEDIATE;');
    try {
      step.apply(db);
      db.userVersion = step.version;
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }
}

void _v3PartsAndSettings(CommonDatabase db) {
  for (final sql in const [
    // A part is the bundle of cuts the user is assigned within an episode
    // ("part B, 11 cuts"). planned_cut_count may be known before the cut
    // list arrives.
    '''
CREATE TABLE parts (
  id INTEGER PRIMARY KEY,
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  label TEXT NOT NULL,
  sort_key TEXT NOT NULL,
  planned_cut_count INTEGER
    CHECK (planned_cut_count IS NULL OR planned_cut_count >= 0),
  note TEXT,
  archived_at INTEGER
);''',
    'CREATE INDEX parts_episode ON parts(episode_id, sort_key);',
    'ALTER TABLE cuts ADD COLUMN part_id INTEGER REFERENCES parts(id);',
    'CREATE INDEX cuts_part ON cuts(part_id);',
    // The part's deadline for a stage; a cut task follows it unless the
    // task sets its own due_at.
    '''
CREATE TABLE part_stage_dues (
  part_id INTEGER NOT NULL REFERENCES parts(id),
  stage_id INTEGER NOT NULL REFERENCES work_stages(id),
  due_at INTEGER NOT NULL,
  PRIMARY KEY (part_id, stage_id)
);''',
    '''
CREATE VIEW task_dues AS
SELECT t.id AS task_id,
       COALESCE(t.due_at, d.due_at) AS due_at,
       t.due_at IS NULL AND d.due_at IS NOT NULL AS from_part
FROM tasks t
LEFT JOIN cuts c ON c.id = t.cut_id
LEFT JOIN part_stage_dues d
  ON d.part_id = c.part_id AND d.stage_id = t.stage_id;''',
    'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);',
    'ALTER TABLE work_intervals ADD COLUMN task_id INTEGER REFERENCES tasks(id);',
    'CREATE INDEX work_intervals_task ON work_intervals(task_id);',
  ]) {
    db.execute(sql);
  }
}

void _v4StagePresets(CommonDatabase db) {
  for (final sql in const [
    // A named, editable list of stages. A new work copies one; editing a
    // preset never changes existing works. Exactly one is the default.
    '''
CREATE TABLE stage_presets (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
);''',
    '''
CREATE UNIQUE INDEX stage_presets_one_default ON stage_presets(is_default)
  WHERE is_default = 1;''',
    '''
CREATE TABLE stage_preset_items (
  id INTEGER PRIMARY KEY,
  preset_id INTEGER NOT NULL REFERENCES stage_presets(id),
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);''',
    '''
CREATE INDEX stage_preset_items_preset
  ON stage_preset_items(preset_id, position);''',
    "INSERT INTO stage_presets (id, name, is_default) VALUES (1, '기본', 1);",
  ]) {
    db.execute(sql);
  }
  // Seeded with a literal copy so this step never changes once shipped,
  // whatever later happens to the factory list in the models.
  const seed = [
    '콘티',
    '콘티 체크',
    'LO',
    'LO 연출 수정',
    'LO 작감 수정',
    'LO 총작감 수정',
    '원화',
    '원화 연출 수정',
    '원화 작감 수정',
    '원화 총작감 수정',
  ];
  for (var i = 0; i < seed.length; i++) {
    db.execute(
      'INSERT INTO stage_preset_items (preset_id, name, position) '
      'VALUES (1, ?, ?);',
      [seed[i], i],
    );
  }
}

void _v5WorkRounding(CommonDatabase db) {
  // NULL follows the app-wide setting.
  db.execute('''
ALTER TABLE works ADD COLUMN seconds_rounding TEXT
  CHECK (seconds_rounding IN ('exact', 'up', 'down', 'nearest'));''');
}

void _v6PlansAndDefaultUnit(CommonDatabase db) {
  for (final sql in const [
    // Preselected when entering an episode's rates; rates keep their own.
    '''
ALTER TABLE works ADD COLUMN default_rate_unit TEXT NOT NULL DEFAULT 'fixed'
  CHECK (default_rate_unit IN ('fixed', 'per_second'));''',
    // The user's own plan for a part × stage, beside the production
    // deadline in part_stage_dues. Either end may be open.
    '''
CREATE TABLE part_stage_plans (
  part_id INTEGER NOT NULL REFERENCES parts(id),
  stage_id INTEGER NOT NULL REFERENCES work_stages(id),
  start_at INTEGER,
  end_at INTEGER,
  PRIMARY KEY (part_id, stage_id),
  CHECK (start_at IS NOT NULL OR end_at IS NOT NULL),
  CHECK (start_at IS NULL OR end_at IS NULL OR end_at >= start_at)
);''',
    // A cut's own plan, overriding its part's field by field.
    'ALTER TABLE tasks ADD COLUMN plan_start_at INTEGER;',
    'ALTER TABLE tasks ADD COLUMN plan_end_at INTEGER;',
  ]) {
    db.execute(sql);
  }
}

void _v7DaysOff(CommonDatabase db) {
  // Calendar days the user does not work (a trip, a holiday), as local
  // ISO dates — whole days, not instants, so they never shift with the
  // time zone. A single day has start = end.
  db.execute('''
CREATE TABLE days_off (
  id INTEGER PRIMARY KEY,
  start_date TEXT NOT NULL CHECK (start_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  end_date TEXT NOT NULL CHECK (end_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  note TEXT,
  CHECK (end_date >= start_date)
);''');
  db.execute('CREATE INDEX days_off_end ON days_off(end_date);');
}

void _v8LiveTasks(CommonDatabase db) {
  // A task is live only when it and everything above it is: archiving a
  // work, episode, part, cut or storyboard hides what lies beneath without
  // touching it, so restoring brings it all back. Hidden stages do not
  // hide their tasks.
  db.execute('''
CREATE VIEW live_tasks AS
SELECT t.* FROM tasks t
JOIN work_stages s ON s.id = t.stage_id
JOIN works w ON w.id = s.work_id
LEFT JOIN cuts c ON c.id = t.cut_id
LEFT JOIN storyboards sb ON sb.id = t.storyboard_id
JOIN episodes e ON e.id = COALESCE(c.episode_id, sb.episode_id)
LEFT JOIN parts p ON p.id = c.part_id
WHERE t.archived_at IS NULL AND w.archived_at IS NULL
  AND e.archived_at IS NULL
  AND (c.id IS NULL OR c.archived_at IS NULL)
  AND (sb.id IS NULL OR sb.archived_at IS NULL)
  AND (p.id IS NULL OR p.archived_at IS NULL);''');
}

void _v9KickoffAndOrder(CommonDatabase db) {
  for (final sql in const [
    // When production work really began for a part × stage (a drawing
    // meeting, say): with the deadline, the production schedule. A cut
    // task may carry its own.
    '''
CREATE TABLE part_stage_kickoffs (
  part_id INTEGER NOT NULL REFERENCES parts(id),
  stage_id INTEGER NOT NULL REFERENCES work_stages(id),
  kickoff_at INTEGER NOT NULL,
  PRIMARY KEY (part_id, stage_id)
);''',
    'ALTER TABLE tasks ADD COLUMN kickoff_at INTEGER;',
    // The user's drag order of schedule units, by group key
    // (part:<part>:<stage>, nopart:<episode>:<stage>, storyboard:<task>).
    '''
CREATE TABLE group_order (
  group_key TEXT PRIMARY KEY,
  position INTEGER NOT NULL
);''',
  ]) {
    db.execute(sql);
  }
}

void _v10RolesPinsSharedCuts(CommonDatabase db) {
  for (final sql in const [
    // A role (원화, 작감 …) names the stages the user takes on; choosing it
    // when registering work creates a task for each of them.
    '''
CREATE TABLE roles (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);''',
    '''
CREATE TABLE role_stages (
  role_id INTEGER NOT NULL REFERENCES roles(id),
  stage_name TEXT NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (role_id, stage_name)
);''',
    // A calendar bar the user dragged to a lane, by group key.
    '''
CREATE TABLE lane_pins (
  group_key TEXT PRIMARY KEY,
  lane INTEGER NOT NULL CHECK (lane >= 0)
);''',
    // Cuts drawn as one shared cut (겸용) keep their own rows, lengths and
    // tasks; they only point at the group's first cut.
    'ALTER TABLE cuts ADD COLUMN shared_with INTEGER REFERENCES cuts(id);',
    'CREATE INDEX cuts_shared ON cuts(shared_with);',
    // How a work writes cut numbers: prefix and zero-padded digits
    // (C + 3 → C001). The user types only the number.
    "ALTER TABLE works ADD COLUMN cut_prefix TEXT NOT NULL DEFAULT 'C';",
    '''
ALTER TABLE works ADD COLUMN cut_digits INTEGER NOT NULL DEFAULT 3
  CHECK (cut_digits BETWEEN 1 AND 8);''',
  ]) {
    db.execute(sql);
  }
  // Seeded with a literal copy so this step never changes once shipped.
  const roles = [
    // Ranks only (user): 원화 · 연출 · 작감 · 총작감 · 콘티.
    ('원화', ['LO', '원화']),
    ('연출', ['LO 연출 수정', '원화 연출 수정']),
    ('작감', ['LO 작감 수정', '원화 작감 수정']),
    ('총작감', ['LO 총작감 수정', '원화 총작감 수정']),
    ('콘티', ['콘티']),
  ];
  for (var i = 0; i < roles.length; i++) {
    db.execute('INSERT INTO roles (name, position) VALUES (?, ?);', [
      roles[i].$1,
      i,
    ]);
    final id = db.lastInsertRowId;
    final stages = roles[i].$2;
    for (var j = 0; j < stages.length; j++) {
      db.execute(
        'INSERT INTO role_stages (role_id, stage_name, position) '
        'VALUES (?, ?, ?);',
        [id, stages[j], j],
      );
    }
  }
}
