import 'package:sqlite3/sqlite3.dart';

/// One forward-only schema step. [version] is the `user_version` the
/// database has after [apply] runs.
class Migration {
  const Migration(this.version, this.apply);

  final int version;
  final void Function(Database db) apply;
}

/// Every migration, oldest first. Append only — never edit a shipped step;
/// a fix is a new step. Versions must be 1, 2, 3, … with no gaps.
///
/// v1: timer intervals. v2: the work catalogue (clients, works, stages,
/// episodes, cuts, storyboards, rates, tasks, retakes). v3: parts with
/// per-stage deadlines, settings, and timer intervals linked to tasks.
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
];

/// Conventions: instants are UTC epoch milliseconds; money is an integer
/// in the currency's smallest unit; rows are soft-deleted via
/// `archived_at` because finished work must stay countable.
void _v2Catalogue(Database db) {
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
      'Database schema v$found is newer than this build supports (v$supported).';
}

/// Brings [db] up to the latest version. Each step runs in its own
/// transaction together with its `user_version` bump, so a crash mid-way
/// leaves the file at the last completed version, never half-migrated.
void migrate(Database db, {List<Migration>? steps}) {
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

void _v3PartsAndSettings(Database db) {
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
