import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/work_interval.dart';

/// Thrown when starting a timer while another is already running.
class TimerAlreadyRunningException implements Exception {
  @override
  String toString() => 'A work timer is already running.';
}

/// Persists timer intervals. Only the start and stop instants are written;
/// elapsed time is computed from them, so the timer survives the app being
/// killed and relaunched.
///
/// Provisional rule (pending the user's answer): at most one timer runs at
/// a time.
class WorkTimerStore {
  WorkTimerStore(this._db, {this.clock = systemClock});

  final Database _db;

  /// Source of "now"; injectable for tests.
  final Clock clock;

  /// The running interval, if any.
  WorkInterval? running() {
    final rows = _db.select(
      'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
      'WHERE stopped_at IS NULL ORDER BY started_at DESC LIMIT 1;',
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Starts a timer now, optionally on [taskId]. Throws if one is already
  /// running.
  WorkInterval start({int? taskId}) {
    if (running() != null) throw TimerAlreadyRunningException();
    final now = clock().toUtc();
    _db.execute(
      'INSERT INTO work_intervals (started_at, task_id) VALUES (?, ?);',
      [now.millisecondsSinceEpoch, taskId],
    );
    return WorkInterval(id: _db.lastInsertRowId, start: now, taskId: taskId);
  }

  /// Stops the running timer now and returns it, or null if none runs.
  /// A clock that moved backwards stops the interval at its own start
  /// (zero length) instead of before it.
  WorkInterval? stop() {
    final open = running();
    if (open == null) return null;
    var now = clock().toUtc();
    if (now.isBefore(open.start)) now = open.start;
    _db.execute('UPDATE work_intervals SET stopped_at = ? WHERE id = ?;', [
      now.millisecondsSinceEpoch,
      open.id,
    ]);
    return WorkInterval(
      id: open.id,
      start: open.start,
      stop: now,
      taskId: open.taskId,
    );
  }

  /// The play/pause button for [taskId]: pauses when its timer runs,
  /// otherwise (re)starts on it — a timer running on another task moves
  /// here. There is no stop or reset: time is only ever recorded. Answers
  /// the running interval, or null when paused.
  WorkInterval? toggle({int? taskId}) {
    final open = running();
    if (open != null) {
      stop();
      if (open.taskId == taskId) return null;
    }
    return start(taskId: taskId);
  }

  /// The user picked [taskId] (a cut). The setting alone decides what
  /// follows, whatever ran before: [autoStart] (`timerAutoStart`) runs the
  /// timer on the picked task, otherwise it ends up paused. Picking the
  /// task the timer already runs on leaves it running; picking nothing
  /// (null) pauses.
  WorkInterval? selectionChanged(int? taskId, {required bool autoStart}) {
    final open = running();
    if (open != null && open.taskId == taskId && taskId != null) return open;
    if (open != null) stop();
    return autoStart && taskId != null ? start(taskId: taskId) : null;
  }

  /// Intervals that overlap `[from, to)`, oldest first, including a
  /// running one.
  List<WorkInterval> overlapping(DateTime from, DateTime to) {
    final rows = _db.select(
      'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
      'WHERE started_at < ? AND (stopped_at IS NULL OR stopped_at > ?) '
      'ORDER BY started_at;',
      [to.millisecondsSinceEpoch, from.millisecondsSinceEpoch],
    );
    return [for (final r in rows) _fromRow(r)];
  }

  /// All time recorded on [taskId] as of now, including a running timer.
  Duration workedOn(int taskId) {
    final rows = _db.select(
      'SELECT id, started_at, stopped_at, task_id FROM work_intervals '
      'WHERE task_id = ?;',
      [taskId],
    );
    return totalElapsed([for (final r in rows) _fromRow(r)], clock().toUtc());
  }

  /// Time worked inside `[from, to)` as of now.
  Duration workedBetween(DateTime from, DateTime to) =>
      totalElapsed(overlapping(from, to), clock().toUtc(), from: from, to: to);

  static WorkInterval _fromRow(Row r) {
    final stopped = r['stopped_at'] as int?;
    return WorkInterval(
      id: r['id'] as int,
      start: _utc(r['started_at'] as int),
      stop: stopped == null ? null : _utc(stopped),
      taskId: r['task_id'] as int?,
    );
  }

  static DateTime _utc(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
