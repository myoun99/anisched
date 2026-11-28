import 'dart:async';

import '../models/catalogue.dart';
import '../models/holidays.dart';
import '../models/lanes.dart';
import '../models/number_style.dart';
import '../models/progress.dart';
import '../models/stats.dart';
import '../models/work_interval.dart';
import 'catalogue_store.dart';

// The background reader needs isolates and a native SQLite connection;
// the web build reads on the same thread ([SyncCatalogueReader]).
export 'catalogue_reader_background.dart'
    if (dart.library.js_interop) 'catalogue_reader_none.dart';

/// One stretch of timer time within a day.
typedef DayInterval = ({
  DateTime start,
  DateTime end,
  bool running,
  int? workId,
  int? taskId,
});

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
    bool includeHandedOff = false,
  });

  /// See [CatalogueStore.today].
  Future<TodayView> today({int horizonDays = 4});

  /// See [CatalogueStore.monthlyTotals].
  Future<MonthlyTotals> monthlyTotals(int year, int month);

  /// See [CatalogueStore.stagePaces].
  Future<List<StagePace>> stagePaces();

  /// See [CatalogueStore.signals].
  Future<Map<String, GroupSignals>> signals({bool includeDone = false});

  /// See [CatalogueStore.weekHours].
  Future<List<({DateTime day, Duration worked})>> weekHours({DateTime? weekOf});

  /// See [CatalogueStore.dayIntervals].
  Future<List<DayInterval>> dayIntervals({DateTime? day});

  /// See [CatalogueStore.workedOn].
  Future<Map<int, Duration>> workedOn(List<int> taskIds);

  /// See [CatalogueStore.runningTimer].
  Future<WorkInterval?> runningTimer();

  /// See [CatalogueStore.dueRevisions].
  Future<List<DueRevision>> dueRevisions(DueTarget target);

  /// See [CatalogueStore.holding].
  Future<({int inHand, int waiting})> holding();

  /// See [CatalogueStore.lanes].
  Future<List<String?>> lanes();

  /// See [CatalogueStore.intervalsOf].
  Future<List<WorkInterval>> intervalsOf(int taskId);

  /// See [CatalogueStore.tasksBeside].
  Future<List<TaskRow>> tasksBeside(int taskId);

  /// See [CatalogueStore.stats].
  Future<Stats> stats({
    required DateTime from,
    required DateTime to,
    StatsBucket bucket = StatsBucket.week,
    int? clientId,
    int? workId,
  });

  /// Pickers for the input screens: see [CatalogueStore.works],
  /// [CatalogueStore.episodes], [CatalogueStore.parts],
  /// [CatalogueStore.cuts] and [CatalogueStore.clients].
  Future<List<({int id, String title, String currency, int? clientId})>>
  works();
  Future<List<({int id, String number, String? title})>> episodes(int workId);
  Future<List<({int id, String label, int? plannedCutCount, int cutCount})>>
  parts(int episodeId);
  Future<List<CutRow>> cuts(int episodeId, {bool includeArchived = false});
  Future<List<ClientRow>> clients();

  /// See [CatalogueStore.calendarLayout].
  Future<({LaneLayout layout, List<String> unplaced})> calendarLayout({
    CalendarBasis basis = CalendarBasis.work,
  });

  /// See [CatalogueStore.hasGroupOrder].
  Future<bool> hasGroupOrder();

  /// See [CatalogueStore.roles].
  Future<List<({int id, String name, List<String> stages})>> roles();

  /// Search for the registration screen: see [CatalogueStore.searchClients],
  /// [CatalogueStore.searchWorks] and [CatalogueStore.searchEpisodes].
  Future<List<ClientRow>> searchClients(String query);
  Future<List<({int id, String title, String currency, int? clientId})>>
  searchWorks(String query, {int? clientId});
  Future<List<({int id, String number, String? title})>> searchEpisodes(
    int workId,
    String query,
  );

  /// See [CatalogueStore.timerTarget].
  Future<int?> timerTarget();

  /// See [CatalogueStore.holidays].
  Future<List<Holiday>> holidays({
    required DateTime from,
    required DateTime to,
  });

  /// See [CatalogueStore.events].
  Future<Map<int?, List<EventRow>>> events({
    required DateTime from,
    required DateTime to,
  });

  /// See [CatalogueStore.numberStyles].
  Future<({NumberStyle cut, NumberStyle episode})> numberStyles();

  /// See [CatalogueStore.archived].
  Future<List<({ArchiveKind kind, int id, String label, DateTime archivedAt})>>
  archived();

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
    bool includeHandedOff = false,
  }) => _run(
    () => store.partGroups(
      workId: workId,
      includeDone: includeDone,
      includeHandedOff: includeHandedOff,
    ),
  );

  @override
  Future<TodayView> today({int horizonDays = 4}) =>
      _run(() => store.today(horizonDays: horizonDays));

  @override
  Future<MonthlyTotals> monthlyTotals(int year, int month) =>
      _run(() => store.monthlyTotals(year, month));

  @override
  Future<List<StagePace>> stagePaces() => _run(store.stagePaces);

  @override
  Future<Map<String, GroupSignals>> signals({bool includeDone = false}) =>
      _run(() => store.signals(includeDone: includeDone));

  @override
  Future<List<({DateTime day, Duration worked})>> weekHours({
    DateTime? weekOf,
  }) => _run(() => store.weekHours(weekOf: weekOf));

  @override
  Future<List<DayInterval>> dayIntervals({DateTime? day}) =>
      _run(() => store.dayIntervals(day: day));

  @override
  Future<Map<int, Duration>> workedOn(List<int> taskIds) =>
      _run(() => store.workedOn(taskIds));

  @override
  Future<WorkInterval?> runningTimer() => _run(store.runningTimer);

  @override
  Future<List<DueRevision>> dueRevisions(DueTarget target) =>
      _run(() => store.dueRevisions(target));

  @override
  Future<({int inHand, int waiting})> holding() => _run(store.holding);

  @override
  Future<List<String?>> lanes() => _run(store.lanes);

  @override
  Future<List<WorkInterval>> intervalsOf(int taskId) =>
      _run(() => store.intervalsOf(taskId));

  @override
  Future<List<TaskRow>> tasksBeside(int taskId) =>
      _run(() => store.tasksBeside(taskId));

  @override
  Future<Stats> stats({
    required DateTime from,
    required DateTime to,
    StatsBucket bucket = StatsBucket.week,
    int? clientId,
    int? workId,
  }) => _run(
    () => store.stats(
      from: from,
      to: to,
      bucket: bucket,
      clientId: clientId,
      workId: workId,
    ),
  );

  @override
  Future<List<({int id, String title, String currency, int? clientId})>>
  works() => _run(store.works);

  @override
  Future<List<({int id, String number, String? title})>> episodes(int workId) =>
      _run(() => store.episodes(workId));

  @override
  Future<List<({int id, String label, int? plannedCutCount, int cutCount})>>
  parts(int episodeId) => _run(() => store.parts(episodeId));

  @override
  Future<List<CutRow>> cuts(int episodeId, {bool includeArchived = false}) =>
      _run(() => store.cuts(episodeId, includeArchived: includeArchived));

  @override
  Future<List<ClientRow>> clients() => _run(store.clients);

  @override
  Future<List<({ArchiveKind kind, int id, String label, DateTime archivedAt})>>
  archived() => _run(store.archived);

  @override
  Future<bool> hasGroupOrder() => _run(() => store.hasGroupOrder);

  @override
  Future<List<({int id, String name, List<String> stages})>> roles() =>
      _run(store.roles);

  @override
  Future<List<ClientRow>> searchClients(String query) =>
      _run(() => store.searchClients(query));

  @override
  Future<List<({int id, String title, String currency, int? clientId})>>
  searchWorks(String query, {int? clientId}) =>
      _run(() => store.searchWorks(query, clientId: clientId));

  @override
  Future<List<({int id, String number, String? title})>> searchEpisodes(
    int workId,
    String query,
  ) => _run(() => store.searchEpisodes(workId, query));

  @override
  Future<({NumberStyle cut, NumberStyle episode})> numberStyles() =>
      _run(store.numberStyles);

  @override
  Future<int?> timerTarget() => _run(store.timerTarget);

  @override
  Future<List<Holiday>> holidays({
    required DateTime from,
    required DateTime to,
  }) => _run(() => store.holidays(from: from, to: to));

  @override
  Future<Map<int?, List<EventRow>>> events({
    required DateTime from,
    required DateTime to,
  }) => _run(() => store.events(from: from, to: to));

  @override
  Future<({LaneLayout layout, List<String> unplaced})> calendarLayout({
    CalendarBasis basis = CalendarBasis.work,
  }) => _run(() => store.calendarLayout(basis: basis));

  @override
  Future<void> close() async => _closed = true;
}
