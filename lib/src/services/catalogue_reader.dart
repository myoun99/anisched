import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../core/clock.dart';
import '../models/progress.dart';
import 'catalogue_store.dart';

/// Monthly pay totals per currency (see [CatalogueStore.monthlyTotals]).
typedef MonthlyTotals = Map<String, ({int total, int unpriced})>;

/// Asynchronous reads for the views. The app uses
/// [BackgroundCatalogueReader], which runs every query off the main
/// isolate; writes stay on the main isolate's [CatalogueStore].
abstract interface class CatalogueReader {
  /// See [CatalogueStore.partGroups].
  Future<List<PartStageRow>> partGroups({
    int? workId,
    bool includeDone = false,
  });

  /// See [CatalogueStore.today].
  Future<TodayView> today({int horizonDays = 4});

  /// See [CatalogueStore.monthlyTotals].
  Future<MonthlyTotals> monthlyTotals(int year, int month);

  /// See [CatalogueStore.usualPaces].
  Future<List<UsualPace>> usualPaces({int days = 28});

  /// Stops the reader. Pending and later reads fail with [StateError].
  Future<void> close();
}

/// Thrown into a read's future when the query failed in the background.
class CatalogueReadException implements Exception {
  CatalogueReadException(this.message, this.remoteStack);

  final String message;

  /// The stack trace from the background isolate, as text.
  final String remoteStack;

  @override
  String toString() => 'CatalogueReadException: $message';
}

/// Runs reads directly on a [CatalogueStore]. For tests only — the app
/// reads through [BackgroundCatalogueReader].
class SyncCatalogueReader implements CatalogueReader {
  SyncCatalogueReader(this.store);

  final CatalogueStore store;
  bool _closed = false;

  Future<T> _run<T>(T Function() read) {
    if (_closed) return Future.error(StateError('The reader is closed.'));
    return Future.sync(read);
  }

  @override
  Future<List<PartStageRow>> partGroups({
    int? workId,
    bool includeDone = false,
  }) => _run(() => store.partGroups(workId: workId, includeDone: includeDone));

  @override
  Future<TodayView> today({int horizonDays = 4}) =>
      _run(() => store.today(horizonDays: horizonDays));

  @override
  Future<MonthlyTotals> monthlyTotals(int year, int month) =>
      _run(() => store.monthlyTotals(year, month));

  @override
  Future<List<UsualPace>> usualPaces({int days = 28}) =>
      _run(() => store.usualPaces(days: days));

  @override
  Future<void> close() async => _closed = true;
}

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
    Database writer,
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
    required Database writer,
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
  }) => _ask((s) => s.partGroups(workId: workId, includeDone: includeDone));

  @override
  Future<TodayView> today({int horizonDays = 4}) =>
      _ask((s) => s.today(horizonDays: horizonDays));

  @override
  Future<MonthlyTotals> monthlyTotals(int year, int month) =>
      _ask((s) => s.monthlyTotals(year, month));

  @override
  Future<List<UsualPace>> usualPaces({int days = 28}) =>
      _ask((s) => s.usualPaces(days: days));

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
