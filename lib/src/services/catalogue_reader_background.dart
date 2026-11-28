import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/catalogue.dart';
import '../models/holidays.dart';
import '../models/lanes.dart';
import '../models/number_style.dart';
import '../models/progress.dart';
import '../models/stats.dart';
import '../models/work_interval.dart';
import 'catalogue_reader.dart';
import 'catalogue_store.dart';

/// One read, run against the background isolate's store.
typedef _Query = Object? Function(CatalogueStore store);

/// Reads on a long-lived background isolate with its own read-only
/// connection to the same database file (WAL lets it read while the main
/// isolate writes).
///
/// Stale answers are never delivered: every write on [writer] bumps a
/// generation number, and a read whose generation changed while it was in
/// flight is asked again, so a future completes with data at least as new
/// as the last write before it completed (after [maxRetries] retries under
/// a constant stream of writes, the latest answer is delivered anyway).
///
/// Errors in a query complete that read's future with a
/// [CatalogueReadException]; if the isolate dies, every pending read fails
/// with a [StateError]. No future is left hanging.
class BackgroundCatalogueReader implements CatalogueReader {
  BackgroundCatalogueReader._(
    this._isolate,
    this._toIsolate,
    this._replies,
    this._exitPort,
    CommonDatabase writer,
    this._clock,
    this._maxRetries,
  ) {
    _exitPort.listen((_) {
      _failAll(StateError('The reader isolate stopped.'));
      if (!_exited.isCompleted) _exited.complete();
    });
    _writes = writer.updatesSync.listen((_) => _generation++);
  }

  /// Opens a reader on the database file at [path]. [writer] is the main
  /// isolate's connection to the same file; its writes mark reads stale.
  /// "Now" for deadlines comes from [clock] on the calling isolate.
  static Future<BackgroundCatalogueReader> open(
    String path, {
    required CommonDatabase writer,
    Clock clock = systemClock,
    int maxRetries = 3,
  }) async {
    final fromIsolate = ReceivePort();
    final exitPort = ReceivePort();
    final started = Completer<Object?>();
    // The first message is the isolate's SendPort (or a setup error);
    // later ones are replies, routed once the reader exists.
    void Function(Object?) route = started.complete;
    final replies = fromIsolate.listen((m) => route(m));
    final isolate = await Isolate.spawn(
      _main,
      (fromIsolate.sendPort, path),
      onExit: exitPort.sendPort,
      debugName: 'catalogue-reader',
    );
    final first = await started.future;
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      await replies.cancel();
      exitPort.close();
      if (first case (final String error, final String stack)) {
        throw CatalogueReadException(error, stack);
      }
      throw StateError('The reader isolate did not start.');
    }
    final reader = BackgroundCatalogueReader._(
      isolate,
      first,
      replies,
      exitPort,
      writer,
      clock,
      maxRetries,
    );
    route = reader._onReply;
    return reader;
  }

  final Isolate _isolate;
  final SendPort _toIsolate;
  final ReceivePort _exitPort;
  final Clock _clock;
  final int _maxRetries;
  final StreamSubscription<Object?> _replies;
  late final StreamSubscription<SqliteUpdate> _writes;
  final _exited = Completer<void>();

  /// Bumped by every write on the main connection.
  int _generation = 0;

  int _nextId = 0;
  final _pending = <int, Completer<Object?>>{};
  bool _closed = false;

  /// The current write generation (for tests and diagnostics).
  int get generation => _generation;

  Future<T> _ask<T>(_Query query) async {
    for (var attempt = 0; ; attempt++) {
      final asked = _generation;
      final answer = await _send(query);
      if (asked == _generation || attempt >= _maxRetries) return answer as T;
    }
  }

  Future<Object?> _send(_Query query) {
    if (_closed) return Future.error(StateError('The reader is closed.'));
    final id = _nextId++;
    final done = Completer<Object?>();
    _pending[id] = done;
    _toIsolate.send((id, _clock(), query));
    return done.future;
  }

  void _onReply(Object? message) {
    switch (message) {
      case (final int id, true, final Object? value):
        _pending.remove(id)?.complete(value);
      case (final int id, false, (final String error, final String stack)):
        _pending
            .remove(id)
            ?.completeError(CatalogueReadException(error, stack));
    }
  }

  void _failAll(Object error) {
    _closed = true;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      c.completeError(error);
    }
    _shutDownPorts();
  }

  void _shutDownPorts() {
    unawaited(_writes.cancel());
    unawaited(_replies.cancel());
    _exitPort.close();
  }

  @override
  Future<List<PartStageRow>> partGroups({
    int? workId,
    bool includeDone = false,
    bool includeHandedOff = false,
  }) => _ask(
    (s) => s.partGroups(
      workId: workId,
      includeDone: includeDone,
      includeHandedOff: includeHandedOff,
    ),
  );

  @override
  Future<TodayView> today({int horizonDays = 4}) =>
      _ask((s) => s.today(horizonDays: horizonDays));

  @override
  Future<MonthlyTotals> monthlyTotals(int year, int month) =>
      _ask((s) => s.monthlyTotals(year, month));

  @override
  Future<List<StagePace>> stagePaces() => _ask((s) => s.stagePaces());

  @override
  Future<Map<String, GroupSignals>> signals({bool includeDone = false}) =>
      _ask((s) => s.signals(includeDone: includeDone));

  @override
  Future<List<({DateTime day, Duration worked})>> weekHours({
    DateTime? weekOf,
  }) => _ask((s) => s.weekHours(weekOf: weekOf));

  @override
  Future<List<DayInterval>> dayIntervals({DateTime? day}) =>
      _ask((s) => s.dayIntervals(day: day));

  @override
  Future<Map<int, Duration>> workedOn(List<int> taskIds) =>
      _ask((s) => s.workedOn(taskIds));

  @override
  Future<WorkInterval?> runningTimer() => _ask((s) => s.runningTimer());

  @override
  Future<List<DueRevision>> dueRevisions(DueTarget target) =>
      _ask((s) => s.dueRevisions(target));

  @override
  Future<({int inHand, int waiting})> holding() => _ask((s) => s.holding());

  @override
  Future<List<String?>> lanes() => _ask((s) => s.lanes());

  @override
  Future<List<WorkInterval>> intervalsOf(int taskId) =>
      _ask((s) => s.intervalsOf(taskId));

  @override
  Future<List<TaskRow>> tasksBeside(int taskId) =>
      _ask((s) => s.tasksBeside(taskId));

  @override
  Future<Stats> stats({
    required DateTime from,
    required DateTime to,
    StatsBucket bucket = StatsBucket.week,
    int? clientId,
    int? workId,
  }) => _ask(
    (s) => s.stats(
      from: from,
      to: to,
      bucket: bucket,
      clientId: clientId,
      workId: workId,
    ),
  );

  @override
  Future<List<({int id, String title, String currency, int? clientId})>>
  works() => _ask((s) => s.works());

  @override
  Future<List<({int id, String number, String? title})>> episodes(int workId) =>
      _ask((s) => s.episodes(workId));

  @override
  Future<List<({int id, String label, int? plannedCutCount, int cutCount})>>
  parts(int episodeId) => _ask((s) => s.parts(episodeId));

  @override
  Future<List<CutRow>> cuts(int episodeId, {bool includeArchived = false}) =>
      _ask((s) => s.cuts(episodeId, includeArchived: includeArchived));

  @override
  Future<List<ClientRow>> clients() => _ask((s) => s.clients());

  @override
  Future<List<({ArchiveKind kind, int id, String label, DateTime archivedAt})>>
  archived() => _ask((s) => s.archived());

  @override
  Future<bool> hasGroupOrder() => _ask((s) => s.hasGroupOrder);

  @override
  Future<List<({int id, String name, List<String> stages})>> roles() =>
      _ask((s) => s.roles());

  @override
  Future<List<ClientRow>> searchClients(String query) =>
      _ask((s) => s.searchClients(query));

  @override
  Future<List<({int id, String title, String currency, int? clientId})>>
  searchWorks(String query, {int? clientId}) =>
      _ask((s) => s.searchWorks(query, clientId: clientId));

  @override
  Future<List<({int id, String number, String? title})>> searchEpisodes(
    int workId,
    String query,
  ) => _ask((s) => s.searchEpisodes(workId, query));

  @override
  Future<List<Holiday>> holidays({
    required DateTime from,
    required DateTime to,
  }) => _ask((s) => s.holidays(from: from, to: to));

  @override
  Future<Map<int?, List<EventRow>>> events({
    required DateTime from,
    required DateTime to,
  }) => _ask((s) => s.events(from: from, to: to));

  @override
  Future<({NumberStyle cut, NumberStyle episode})> numberStyles() =>
      _ask((s) => s.numberStyles());

  @override
  Future<({LaneLayout layout, List<String> unplaced})> calendarLayout({
    CalendarBasis basis = CalendarBasis.work,
  }) => _ask((s) => s.calendarLayout(basis: basis));

  @override
  Future<void> close() async {
    if (_closed) return;
    _toIsolate.send(null); // asks the isolate to close its db and exit
    await _exited.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => _isolate.kill(priority: Isolate.immediate),
    );
    _failAll(StateError('The reader is closed.'));
  }

  /// For tests: kills the isolate as a crash would.
  void debugKill() => _isolate.kill(priority: Isolate.immediate);

  static void _main((SendPort, String) args) {
    final (reply, path) = args;
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly)
        ..execute('PRAGMA query_only = ON;');
    } on Object catch (e, st) {
      reply.send(('$e', '$st'));
      return;
    }
    var now = DateTime.now();
    final store = CatalogueStore(db, clock: () => now);
    final inbox = RawReceivePort();
    inbox.handler = (Object? message) {
      if (message case (final int id, final DateTime at, final _Query query)) {
        now = at;
        try {
          reply.send((id, true, query(store)));
        } on Object catch (e, st) {
          reply.send((id, false, ('$e', '$st')));
        }
      } else {
        db.close();
        inbox.close();
        Isolate.exit();
      }
    };
    reply.send(inbox.sendPort);
  }
}
