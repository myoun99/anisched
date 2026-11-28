import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide UndoHistory;
import 'package:flutter/services.dart';

import '../controllers/registration.dart';
import '../controllers/unit_actions.dart';
import '../core/clock.dart';
import '../core/size_class.dart';
import '../models/lanes.dart';
import '../models/progress.dart';
import '../models/catalogue.dart';
import '../services/catalogue_reader.dart';
import '../services/catalogue_store.dart';
import '../services/document_session.dart';
import '../services/undo_history.dart';
import '../services/work_timer.dart';
import 'add_cuts.dart';
import 'bundle_editor.dart';
import 'client_chip.dart';
import 'delete_confirm.dart';
import 'document_menu.dart';
import 'empty_start.dart';
import 'event_editor.dart';
import 'filter.dart';
import 'format.dart';
import 'hold.dart';
import 'instant.dart';
import 'palette.dart';
import 'part_line.dart';
import 'pick_field.dart';
import 'time_editor.dart';
import 'selection.dart';
import 'selection_bar.dart';
import 'theme.dart';
import 'timer_bar.dart';
import 'undo.dart';
import 'widgets.dart';
import 'views/chart.dart';
import 'views/register_view.dart';
import 'views/settings_view.dart';
import 'views/sheet_view.dart';
import 'views/stats_view.dart';
import 'views/timeline_view.dart';
import 'views/work_view.dart';
import 'text/strings.dart';
import 'fit_text.dart';

/// The app's views: the list, the production timeline, the user's own
/// work on parallel lanes, registration and settings.
enum AppView {
  list(S.viewList),
  timeline(S.viewTimeline),
  work(S.viewWork),
  register(S.viewRegister),
  stats(S.viewStats),
  settings(S.viewSettings);

  const AppView(this.word);

  final S word;

  String get label => word.t;
}

/// App frame: a top bar, the current view, and the view switcher along
/// the bottom — the same on every screen.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialView = AppView.list,
    this.reader,
    this.store,
    this.timer,
    this.clock = systemClock,
    this.session,
    this.picker = const PlatformPicker(),
    this.remote,
    this.onSample,
  });

  /// Fills an empty document with example work (the web preview's first
  /// run); null offers only 등록.
  final void Function(CatalogueStore store)? onSample;

  final AppView initialView;

  /// Reads the user's catalogue off the main isolate; null shows empty
  /// views.
  final CatalogueReader? reader;

  /// Writes on the main isolate (status changes); null keeps the app
  /// read-only.
  final CatalogueStore? store;

  /// The work timer's store (writes on the main isolate).
  final WorkTimerStore? timer;

  /// Source of "now" for deadlines; injectable for tests.
  final Clock clock;

  /// The document this app edits (autosave, open, save as); null hides
  /// the file menu.
  final DocumentSessionBase? session;
  final DocumentPicker picker;

  /// The last resume check, for the save-state icon.
  final ValueListenable<RemoteCheck?>? remote;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppView _view = widget.initialView;
  List<PartGroup> _groups = const [];

  /// Rest weekdays, days off and holidays, for the charts' backgrounds.
  ChartDays _days = const ChartDays();

  /// Dated events by episode, for the timeline.
  Map<int?, List<EventRow>> _events = const {};

  /// Events of one card, by its key (a long press on its bar).
  Map<String, List<EventRow>> _cardEvents = const {};

  /// The first read has come back (an empty document is then truly empty).
  bool _loaded = false;
  Map<String, GroupSignals> _signals = const {};
  Map<String, StagePace> _paces = const {};
  LaneLayout? _lanes;
  ViewFilter _filter = const ViewFilter();
  Map<int, ({String title, int? clientId})> _works = const {};
  Map<int, ClientTag> _clients = const {};
  List<({int id, String name, List<String> stages})> _roles = const [];
  final _selection = TaskSelection();
  int _refresh = 0;

  StreamSubscription<DocumentChange>? _doc;

  @override
  void dispose() {
    unawaited(_doc?.cancel());
    _selection.dispose();
    super.dispose();
  }

  void _onDocument(DocumentChange change) {
    if (!mounted) return;
    if (change == DocumentChange.content) {
      setState(() => _refresh++);
      unawaited(_loadGroups());
    } else {
      setState(() {});
    }
  }

  /// Moves every picked task to [status], then reloads the views.
  void _apply(TaskStatus status) {
    final store = widget.store;
    if (store == null || _selection.isEmpty) return;
    store.setStatusMany(_selection.ids, status);
    _selection.clear();
    setState(() => _refresh++);
    unawaited(_loadGroups());
  }

  @override
  void initState() {
    super.initState();
    _timerTask = widget.timer?.running()?.taskId;
    if (_timerTask == null) unawaited(_restoreTimerTarget());
    if (widget.store case final s?) {
      episodeStyle.value = s.settings.episodeStyle;
    }
    _doc = widget.session?.changes.listen(_onDocument);
    unawaited(_loadGroups());
  }

  /// Reloads the sheet's groups; the last ones stay on screen meanwhile.
  Future<void> _loadGroups() async {
    final reader = widget.reader;
    if (reader == null) return;
    final done = _filter.showDone;
    final today = widget.clock();
    // Events of one card (its bar), by card key: loaded alongside.
    final cardsLoading = reader.cardEvents(
      from: today.subtract(const Duration(days: 120)),
      to: today.add(const Duration(days: 240)),
    );
    final (
      groups,
      signals,
      paces,
      lanes,
      works,
      clients,
      roles,
      events,
      holidays,
    ) = await (
      reader.partGroups(
        // Archived work is often handed in: listed then too.
        includeDone: done || _filter.showArchived,
        includeHandedOff: _filter.showHandedOff,
        includeArchived: _filter.showArchived,
      ),
      reader.signals(includeDone: done),
      reader.stagePaces(),
      reader.calendarLayout(basis: CalendarBasis.work),
      reader.works(),
      reader.clients(),
      reader.roles(),
      // Events a few months either side (the chart scrolls).
      reader.events(
        from: today.subtract(const Duration(days: 120)),
        to: today.add(const Duration(days: 240)),
      ),
      reader.holidays(
        from: today.subtract(const Duration(days: 120)),
        to: today.add(const Duration(days: 240)),
      ),
    ).wait;
    final cards = await cardsLoading;
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _events = events;
      _cardEvents = cards;
      final st = widget.store;
      _days = ChartDays(
        restWeekdays:
            st?.settings.restWeekdays ??
            const {DateTime.saturday, DateTime.sunday},
        daysOff: [
          if (st != null)
            for (final d in st.restDays()) DaysOff(d.date),
        ],
        holidays: st == null || st.settings.showHolidays
            ? {for (final h in holidays) h.date: h.name}
            : const {},
        events: events[null] ?? const [],
      );
      _works = {
        for (final w in works) w.id: (title: w.title, clientId: w.clientId),
      };
      _clients = {
        for (final c in clients)
          c.id: (name: c.name, color: clientColorOf(c.id, c.color)),
      };
      _roles = roles;
      _groups = groups;
      _signals = signals;
      _paces = {for (final p in paces) p.stageName: p};
      _lanes = lanes.layout;
    });
  }

  /// A new event on [g]'s episode, on [day] (a long press on the
  /// timeline).
  Future<void> _newEvent(PartGroup g, DateTime day) async {
    final a = await showEventEditor(context, day: day);
    if (a is! EventSave) return;
    // On that card alone (its bar), not the whole episode.
    _write(
      (s) => s.addEvent(
        card: g.key,
        date: day,
        timeMinutes: a.timeMinutes,
        title: a.title,
        note: a.note,
      ),
    );
  }

  /// A new event of no episode on [day] (a long press on the date
  /// ruler): a day off, or a dated note.
  Future<void> _newRulerEvent(DateTime day) async {
    final a = await showEventEditor(context, day: day, global: true);
    if (a is! EventSave) return;
    _write(
      (s) => s.addEvent(
        date: day,
        timeMinutes: a.timeMinutes,
        title: a.title,
        note: a.note,
        rest: a.rest,
      ),
    );
  }

  /// An event tapped: the same window edits or removes it.
  Future<void> _editEvent(EventRow e) async {
    final a = await showEventEditor(
      context,
      day: e.date,
      existing: e,
      global: e.episodeId == null,
    );
    switch (a) {
      case EventSave():
        _write(
          (s) => s.updateEvent(
            e.id,
            episodeId: e.episodeId,
            date: e.date,
            timeMinutes: a.timeMinutes,
            title: a.title,
            note: a.note,
            rest: a.rest,
          ),
        );
      case EventRemove():
        _write((s) => s.deleteEvent(e.id));
      case null:
    }
  }

  /// A unit's client: its work's, with the client's colour.
  ClientTag? _clientOf(PartGroup g) {
    final id = _works[g.workId]?.clientId;
    return id == null ? null : _clients[id];
  }

  /// The cut last put on the time bar, back on it (paused).
  Future<void> _restoreTimerTarget() async {
    final id = await widget.reader?.timerTarget();
    if (id != null && mounted && _timerTask == null) {
      setState(() => _timerTask = id);
    }
  }

  /// The task the timer last ran on, for resume.
  int? _timerTask;

  /// The cut on the time bar and its unit — from the sheet, or (when the
  /// sheet hides it, e.g. just submitted) straight from the store, so the
  /// bar keeps its cut.
  (TaskRow, PartGroup)? _timerTarget(int? id) {
    if (id == null) return null;
    for (final g in _groups) {
      for (final t in g.tasks) {
        if (t.id == id) return (t, g);
      }
    }
    final row = widget.store
        ?.taskRows(includeDone: true)
        .where((t) => t.id == id)
        .firstOrNull;
    return row == null ? null : (row, PartGroup([row]));
  }

  Widget _timerBar() {
    final timer = widget.timer;
    final running = timer?.running();
    final id = running?.taskId ?? _timerTask;
    final target = _timerTarget(id);
    final on = running != null && running.taskId == id;
    final writable = widget.store != null;
    return TimerBar(
      running: on,
      task: target?.$1,
      group: target?.$2,
      clock: widget.clock,
      worked: timer == null || id == null ? null : () => timer.workedOn(id),
      onToggle: timer == null || id == null
          ? null
          : () {
              timer.toggle(taskId: id);
              setState(() => _timerTask = id);
            },
      onPickCut: timer == null ? null : () => _pickTimerCut(target?.$1),
      onPickWork: target == null ? null : () => _pickTimerWork(target.$2),
      onPickEpisode: target == null
          ? null
          : () => _pickTimerEpisode(target.$2.workId, target.$2.episodeId),
      onStatus: !writable || id == null
          ? null
          : (st) => _write((store) => store.setStatus(id, st)),
      onEditTime: timer == null || target == null || widget.reader == null
          ? null
          : () => unawaited(
              showTimeEditor(
                context,
                title: taskLabel(target.$1),
                now: widget.clock(),
                edits: TimeEdits(
                  load: () => widget.reader!.intervalsOf(target.$1.id),
                  edit: (i, {start, stop}) {
                    timer.editInterval(i, start: start, stop: stop);
                    setState(() => _refresh++);
                  },
                  add: (a, b) {
                    timer.addInterval(taskId: target.$1.id, start: a, stop: b);
                    setState(() => _refresh++);
                  },
                  delete: (i) {
                    timer.deleteInterval(i);
                    setState(() => _refresh++);
                  },
                ),
              ),
            ),
    );
  }

  /// The time bar's cut: the others of its episode, in cut order, the
  /// current one in the middle; with none on the bar yet, every cut with
  /// work left.
  Future<void> _pickTimerCut(TaskRow? now) async {
    final reader = widget.reader;
    if (reader == null) return;
    final rows =
        [
          if (now != null) ...[
            now,
            ...await reader.tasksBeside(now.id),
          ] else
            for (final g in _groups)
              for (final t in g.tasks)
                if (t.status.needsWork) t,
        ]..sort((a, b) {
          final k = naturalSortKey(taskLabel(a))
              .compareTo(naturalSortKey(taskLabel(b)));
          return k != 0 ? k : a.stageName.compareTo(b.stageName);
        });
    if (!mounted) return;
    // A shared group is one cut here too: its first task, its numbers.
    final units = cutUnits(rows);
    final current = now == null
        ? null
        : units.firstWhere((u) => u.any((t) => t.id == now.id)).first.id;
    final picked = await showCenteredPicker<int>(
      context: context,
      title: S.cutName.t,
      current: current,
      searchable: units.length > 12,
      search: (q) async => [
        for (final u in units)
          if (u.first case final t when q.isEmpty || unitText(u).contains(q))
            (
              value: t.id,
              title: unitText(u),
              note: [
                stageText(t.stageName),
                if (t.partLabel case final p?) S.partTitle.f({'p': p}),
              ].join(' · '),
            ),
      ],
    );
    if (picked != null) _pickForTimer(picked.value);
  }

  /// Another title: then its episode, then that episode's first cut.
  Future<void> _pickTimerWork(PartGroup now) async {
    final works = <int, String>{for (final g in _groups) g.workId: g.workTitle};
    final keys = works.keys.toList()
      ..sort(
        (a, b) =>
            naturalSortKey(works[a]!).compareTo(naturalSortKey(works[b]!)),
      );
    final picked = await showCenteredPicker<int>(
      context: context,
      title: S.title.t,
      current: now.workId,
      searchable: keys.length > 12,
      search: (q) async => [
        for (final k in keys)
          if (q.isEmpty || works[k]!.contains(q))
            (value: k, title: works[k]!, note: null),
      ],
    );
    if (picked == null || !mounted) return;
    await _pickTimerEpisode(picked.value, null);
  }

  /// An episode of [workId]; the bar moves to its first cut.
  Future<void> _pickTimerEpisode(int workId, int? current) async {
    final eps = <int, String>{
      for (final g in _groups)
        if (g.workId == workId) g.episodeId: g.episodeNumber,
    };
    final keys = eps.keys.toList()
      ..sort(
        (a, b) => naturalSortKey(eps[a]!).compareTo(naturalSortKey(eps[b]!)),
      );
    final picked = keys.length == 1 && current == null
        ? (value: keys.single, title: '', note: null)
        : await showCenteredPicker<int>(
            context: context,
            title: S.episode.t,
            current: current,
            searchable: keys.length > 12,
            search: (q) async => [
              for (final k in keys)
                if (q.isEmpty || eps[k]!.contains(q))
                  (value: k, title: eps[k]!, note: null),
            ],
          );
    if (picked == null || picked.value == current) return;
    final first = _groups
        .where((g) => g.episodeId == picked.value)
        .expand((g) => g.tasks)
        .firstOrNull;
    if (first != null) _pickForTimer(first.id);
  }

  /// Puts a cut on the time bar. Recording starts only when the user
  /// chose that in settings; otherwise the bar waits, paused.
  void _pickForTimer(int taskId) {
    final timer = widget.timer;
    if (timer == null) return;
    timer.selectionChanged(
      taskId,
      autoStart: widget.store?.settings.timerAutoStart ?? false,
    );
    // Remembered for the next start (not started then, by itself).
    widget.store?.setTimerTarget(taskId);
    setState(() => _timerTask = taskId);
  }

  /// Runs one write on the store, then reloads every view.
  void _write(void Function(CatalogueStore store) body) {
    final store = widget.store;
    if (store == null) return;
    // All or nothing, and one undo step.
    store.batch(() => body(store));
    _reloadAll();
  }

  /// Every view reads the document again.
  void _reloadAll() {
    final store = widget.store;
    if (store != null) episodeStyle.value = store.settings.episodeStyle;
    setState(() => _refresh++);
    unawaited(_loadGroups());
  }

  /// The document's undo history (every write is a step), if recorded.
  UndoHistory? get _history =>
      widget.store == null ? null : UndoHistory.of(widget.store!.db);

  /// Takes back the last write (the keys and ↶), then reloads the views.
  void _undo() {
    if (_history?.undo() ?? false) _reloadAll();
  }

  void _redo() {
    if (_history?.redo() ?? false) _reloadAll();
  }

  void _setFilter(ViewFilter f) {
    final reload =
        f.showDone != _filter.showDone ||
        f.showHandedOff != _filter.showHandedOff ||
        f.showArchived != _filter.showArchived;
    setState(() => _filter = f);
    if (reload) unawaited(_loadGroups());
  }

  /// Units passing the filter, in the stored order.
  List<PartGroup> _visible(DateTime now) {
    final clientOf = {for (final e in _works.entries) e.key: e.value.clientId};
    return [
      for (final g in _groups)
        if (_filter.matches(g, now, clientOf)) g,
    ];
  }

  /// A drag in the list: [shownKeys] in their new order. Hidden units
  /// keep their slots.
  void _reorder(List<String> shownKeys) => _write((store) {
    final shown = shownKeys.toSet();
    final next = shownKeys.iterator;
    store.setGroupOrder([
      for (final g in _groups)
        if (shown.contains(g.key)) (next..moveNext()).current else g.key,
    ]);
  });

  /// The shared filter: the list, the timeline and the statistics.
  Widget _filterButton() => FilterButton(
    filter: _filter,
    onChanged: _setFilter,
    clients: _clients,
    works: {
      for (final w in _works.entries)
        if (_groups.any((g) => g.workId == w.key)) w.key: w.value.title,
    },
  );

  List<Widget> _toolbar() => [
    ToolbarButton(
      key: const Key('sort-by-due'),
      label: S.sortByDue.t,
      icon: Icons.sort,
      selected: false,
      onTap: widget.store == null
          ? null
          : () => _write((s) => s.clearGroupOrder()),
    ),
    _filterButton(),
  ];

  static DateTime _startOf(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOf(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59);

  /// A timeline bar dropped: the unit's production kickoff and deadline.
  void _schedule(PartGroup g, DateTime kickoff, DateTime due) =>
      _write((store) {
        final k = _startOf(kickoff);
        final d = _endOf(due);
        if (g.kind == GroupKind.part) {
          store.setPartSchedule(g.partId!, g.stageId, kickoffAt: k, dueAt: d);
        } else {
          for (final t in g.tasks) {
            store.setTaskKickoff(t.id, k);
            store.setTaskDue(t.id, d);
          }
        }
      });

  /// A deadline picked (D label, details or timeline): a new round — the
  /// deadline was extended (2차 …), or the 1st when there was none.
  void _setDue(PartGroup g, DateTime due) => _write((store) {
    for (final target in dueTargets(g)) {
      store.extendDue(target, due);
    }
  });

  /// The rounds of a unit's deadline (one target: a part or storyboard).
  Future<List<DueRevision>> _revisions(PartGroup g) async {
    final reader = widget.reader;
    final targets = dueTargets(g);
    if (reader == null || targets.length != 1) return const [];
    return reader.dueRevisions(targets.single);
  }

  /// Corrects one round of a unit's deadline.
  void _editRevision(PartGroup g, int revision, DateTime due) =>
      _write((store) {
        for (final target in dueTargets(g)) {
          store.editDueRevision(target, revision, due);
        }
      });

  /// Puts [tasks] on hold, asking why and until when — or, when every open
  /// one already waits, takes them off. Whole parts are held as parts, so
  /// cuts added later follow.
  Future<void> _toggleHold(List<TaskRow> tasks) async {
    final plan = HoldPlan.of(_groups, tasks);
    if (widget.store == null || plan.isEmpty) return;
    final note = plan.release ? null : await askHold(context);
    if (!plan.release && note == null) return;
    _write(
      (store) => plan.apply(store, reason: note?.reason, until: note?.until),
    );
    _selection.clear();
  }

  /// Takes the picked tasks off the user (work moved to someone else) at
  /// once, with an undo; picked tasks already pulled come back instead.
  void _handOff() {
    final (:back, :ids) = planHandOff(_pickedTasks);
    if (widget.store == null || ids.isEmpty) return;
    _write((store) => back ? store.undoHandOff(ids) : store.handOff(ids));
    _selection.clear();
    if (back) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('dropped-snack'),
          content: Text('${S.dropped.t} · ${S.items.f({'n': ids.length})}'),
          action: SnackBarAction(
            key: const Key('dropped-undo'),
            label: S.undoDrop.t,
            onPressed: () => _write((store) => store.undoHandOff(ids)),
          ),
        ),
      );
  }

  /// Puts the picked tasks away (보관) at once, with an undo; when every
  /// one is already put away (shown by the filter), brings them back —
  /// or says why not, when the same cut × stage is in work again.
  void _archive() {
    final picked = _pickedTasks;
    final ids = [for (final t in picked) t.id];
    if (widget.store == null || ids.isEmpty) return;
    final back = picked.every((t) => t.archived);
    if (back) {
      _restore(ids);
      return;
    }
    _write((store) => store.archiveTasks(ids));
    _selection.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('archived-snack'),
          content: Text('${S.archive.t} · ${S.items.f({'n': ids.length})}'),
          action: SnackBarAction(
            key: const Key('archived-undo'),
            label: S.undoDrop.t,
            onPressed: () => _restore(ids),
          ),
        ),
      );
  }

  void _restore(List<int> ids) {
    try {
      _write((store) => store.restoreTasks(ids));
      _selection.clear();
    } on StateError {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('restore-blocked'),
            content: Text(S.restoreBlocked.t),
          ),
        );
    }
  }

  /// Edits the picked bundle's names: its client, the work's title (all
  /// its episodes), the episode's number and subtitle, the part's label.
  Future<void> _edit() async {
    final picked = _pickedTasks;
    if (widget.store == null || picked.isEmpty || !oneBundle(picked)) return;
    final t = picked.first;
    final episodes = await widget.reader?.episodes(t.workId) ?? const [];
    if (!mounted) return;
    final clientId = _works[t.workId]?.clientId;
    final e = await editBundle(
      context,
      initial: (
        clientId: clientId,
        workTitle: t.workTitle,
        episodeNumber: t.episodeNumber,
        episodeTitle: episodes
            .where((x) => x.id == t.episodeId)
            .firstOrNull
            ?.title,
        partLabel: t.partId == null ? null : t.partLabel,
      ),
      clientName: clientId == null ? null : _clients[clientId]?.name,
      reader: widget.reader,
      onCreateClient: (name) {
        var id = 0;
        _write((s) => id = s.addClient(name));
        return id;
      },
      onClientColor: (id, argb) => _write((s) => s.setClientColor(id, argb)),
    );
    if (e == null || !mounted) return;
    _write((store) => applyBundleEdit(store, t, e));
    _selection.clear();
  }

  /// Adds cuts to unit [g] (its 「+」): numbers picked as on the register
  /// screen, then cuts with [g]'s stage task under its deadline.
  Future<void> _addCuts(PartGroup g) async {
    final store = widget.store;
    if (store == null) return;
    final names = await askNewCuts(
      context,
      style: store.settings.cutStyle,
      taken: {for (final c in store.cuts(g.episodeId)) c.number},
    );
    if (names == null || !mounted) return;
    _write((store) => addCutsToUnit(store, g, names));
  }

  /// Joins the picked cuts as shared, or takes their group apart.
  void _share() {
    final picked = _pickedTasks;
    final a = shareActionFor(picked);
    if (a == null) return;
    _write((s) => applyShare(s, picked, a));
    _selection.clear();
  }

  /// Renames the one picked cut; a number already in its episode is
  /// refused with a note.
  Future<void> _renameCut() async {
    final picked = _pickedTasks;
    final cuts = pickedCuts(picked);
    if (cuts.length != 1) return;
    final t = picked.firstWhere((t) => t.cutId == cuts.single);
    final name = await askName(
      context,
      title: S.cutName.t,
      initial: t.cutNumber ?? '',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      _write((s) => s.renumberCuts({cuts.single: name.trim()}));
      _selection.clear();
    } on StateError {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('rename-clash'),
            content: Text(S.cutsTaken.f({'names': name.trim()})),
          ),
        );
    }
  }

  /// Takes the picked cuts out (missing numbers: every stage of them) at
  /// once; the snack bar's undo puts them back.
  void _takeOut() {
    final cuts = pickedCuts(_pickedTasks);
    if (cuts.isEmpty) return;
    _write((s) => s.removeCutIds(cuts));
    _selection.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('takeout-snack'),
          content: Text('${S.takeOut.t} · ${cuts.length} cut'),
          action: SnackBarAction(
            key: const Key('takeout-undo'),
            label: S.undoDrop.t,
            onPressed: () => _write((s) => putBack(s, cuts)),
          ),
        ),
      );
  }

  /// Deletes the picked tasks for good, after a confirmation that says
  /// what goes with them (cuts, emptied episodes and titles, timer time).
  Future<void> _delete() async {
    final store = widget.store;
    final ids = [for (final t in _pickedTasks) t.id];
    if (store == null || ids.isEmpty) return;
    final ok = await confirmDelete(context, store.deletionSummary(ids));
    if (ok != true || !mounted) return;
    _write((store) => store.deleteTasks(ids));
    _selection.clear();
  }

  /// The picked cuts' own deadline: one date, a new round for each cut
  /// (their own deadline over the part's).
  Future<void> _dueForPicked() async {
    final picked = _pickedTasks;
    if (picked.isEmpty) return;
    final now = widget.clock();
    final d = await showInstantDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDate: (picked.first.dueAt ?? now).toLocal(),
      title: S.pickDue.t,
    );
    if (d == null || !mounted) return;
    final due = DateTime(d.year, d.month, d.day, 23, 59);
    _write((store) {
      for (final t in picked) {
        store.extendDue(DueTarget.task(t.id), due);
      }
    });
    _selection.clear();
  }

  /// The picked tasks, for the selection bar's hold button.
  List<TaskRow> get _pickedTasks {
    final ids = _selection.ids;
    return [
      for (final g in _groups)
        for (final t in g.tasks)
          if (ids.contains(t.id)) t,
    ];
  }

  /// The production start (착수) picked in the details.
  void _setKickoff(PartGroup g, DateTime kickoff) => _write((store) {
    final k = _startOf(kickoff);
    if (g.kind == GroupKind.part) {
      store.setPartKickoff(g.partId!, g.stageId, k);
    } else {
      for (final t in g.tasks) {
        store.setTaskKickoff(t.id, k);
      }
    }
  });

  /// A work bar's end dragged: the user's own start and end.
  void _plan(PartGroup g, DateTime start, DateTime end) => _write((store) {
    final a = _startOf(start);
    // An end picked before the start ends on the start day.
    final b = _endOf(end.isBefore(a) ? start : end);
    if (g.kind == GroupKind.part) {
      store.setPartPlan(g.partId!, g.stageId, start: a, end: b);
    } else {
      for (final t in g.tasks) {
        store.setTaskPlan(t.id, start: a, end: b);
      }
    }
  });

  void _select(AppView v) {
    if (v != _view) setState(() => _view = v);
  }

  Widget _viewFor(AppView v, ScreenLayout layout) {
    const plans = {AppView.list, AppView.timeline, AppView.work};
    if (_loaded && _works.isEmpty && plans.contains(v)) {
      final sample = widget.onSample;
      final store = widget.store;
      return EmptyStart(
        onRegister: () => _select(AppView.register),
        onSample: sample == null || store == null ? null : () => _write(sample),
      );
    }
    final now = widget.clock();
    final writable = widget.store != null;
    final shown = _visible(now);
    final toolbar = _toolbar();
    // One wiring for every view that opens a unit's details.
    final wiring = UnitWiring(
      now: now,
      dayStartMinutes: widget.store?.settings.dayStartMinutes ?? 0,
      signals: _signals,
      paces: _paces,
      selection: _selection,
      clientOf: _clientOf,
      onDue: writable ? _setDue : null,
      onHold: writable ? (g) => unawaited(_toggleHold(g.tasks)) : null,
      onKickoff: writable ? _setKickoff : null,
      onPlan: writable ? _plan : null,
      revisionsOf: widget.reader == null ? null : _revisions,
      onEditRevision: writable ? _editRevision : null,
      onAddCuts: writable ? (g) => unawaited(_addCuts(g)) : null,
      onTaskTap: widget.timer == null
          ? null
          // A shared group's chip runs the timer on its first cut, and
          // is picked whole.
          : (u) => _selection.isEmpty
                ? _pickForTimer(u.first.id)
                : _selection.toggleUnit(u),
    );
    return switch (v) {
      AppView.list => SheetView(
        parts: shown,
        now: now,
        layout: layout,
        showDone: _filter.showDone,
        wiring: wiring,
        toolbar: toolbar,
        onReorder: writable ? _reorder : null,
      ),
      AppView.timeline => TimelineView(
        parts: shown,
        toolbar: toolbar,
        onReorder: writable ? _reorder : null,
        onDue: writable ? _setDue : null,
        now: now,
        layout: layout,
        days: _days,
        selection: _selection,
        onSchedule: writable ? _schedule : null,
        details: (g) => wiring.details(g, client: true),
        events: _events,
        cardEvents: _cardEvents,
        onNewEvent: writable ? _newEvent : null,
        onEvent: writable ? _editEvent : null,
        onRulerPress: writable ? _newRulerEvent : null,
      ),
      AppView.work => WorkView(
        lanes: _lanes,
        wiring: wiring,
        parts: {for (final g in _groups) g.key: g},
        now: now,
        layout: layout,
        days: _days,
        onRulerPress: writable ? _newRulerEvent : null,
        onRulerEvent: writable ? _editEvent : null,
        onPin: writable
            ? (key, lane) => _write((s) => s.pinLane(key, lane))
            : null,
        onClearPins: writable ? () => _write((s) => s.clearLanePins()) : null,
        onPlan: writable ? _plan : null,
        laneNames: widget.store?.lanes() ?? const [],
        onAddLane: writable ? () => _write((s) => s.addLane()) : null,
        onEditLane: writable
            ? (lane, {name, remove = false}) => _write(
                (s) => remove ? s.removeLane(lane) : s.renameLane(lane, name),
              )
            : null,
      ),
      AppView.register => RegisterView(
        now: now,
        layout: layout,
        reader: widget.reader,
        roles: _roles,
        onCreateClient: writable
            ? (name) {
                var id = 0;
                _write((s) => id = s.addClient(name));
                return id;
              }
            : null,
        onCreateWork: writable
            ? (title, client) {
                var id = 0;
                _write((s) => id = s.createWork(title, clientId: client));
                return id;
              }
            : null,
        onCreateEpisode: writable
            ? (work, typed) {
                var id = 0;
                // The store keeps the typed number's value (#07 → 7).
                _write((s) => id = s.addEpisode(work, typed));
                return id;
              }
            : null,
        onClientColor: writable
            ? (id, argb) => _write((s) => s.setClientColor(id, argb))
            : null,
        onRegister: writable
            ? (draft) {
                var n = 0;
                _write((s) => n = register(s, draft).length);
                return n;
              }
            : null,
      ),
      AppView.stats => StatsView(
        now: now,
        layout: layout,
        reader: widget.reader,
        visible: _view == AppView.stats,
        refresh: _refresh,
        clientId: _filter.clientId,
        workId: _filter.workId,
        clients: _clients,
        filter: _filterButton(),
      ),
      AppView.settings => SettingsView(
        now: now,
        session: widget.session,
        remote: widget.remote,
        store: widget.store,
        reader: widget.reader,
        paces: _paces,
        refresh: _refresh,
        onChanged: () {
          setState(() => _refresh++);
          unawaited(_loadGroups());
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = ScreenLayout.of(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final narrow = layout.size == SizeClass.narrow;
        final selectionBar = SelectionBar(
          selection: _selection,
          onApply: widget.store == null ? null : _apply,
          onHold: widget.store == null
              ? null
              : () => unawaited(_toggleHold(_pickedTasks)),
          onHandOff: widget.store == null ? null : _handOff,
          onDue: widget.store == null ? null : () => unawaited(_dueForPicked()),
          onArchive: widget.store == null ? null : _archive,
          allArchived: () {
            final p = _pickedTasks;
            return p.isNotEmpty && p.every((t) => t.archived);
          },
          onDelete: widget.store == null ? null : () => unawaited(_delete()),
          onEdit: widget.store == null ? null : () => unawaited(_edit()),
          canEdit: () => oneBundle(_pickedTasks),
          onShare: widget.store == null ? null : _share,
          share: () => shareActionFor(_pickedTasks),
          onRename: widget.store == null ? null : () => unawaited(_renameCut()),
          onSplit: widget.store == null
              ? null
              : () {
                  final picked = _pickedTasks;
                  _write((s) => splitPicked(s, picked));
                  _selection.clear();
                },
          onTakeOut: widget.store == null ? null : _takeOut,
          cutCount: () => pickedCuts(_pickedTasks).length,
          allHandedOff: () {
            final p = _pickedTasks;
            return p.isNotEmpty && p.every((t) => t.handedOff);
          },
          allWaiting: () {
            final open = _pickedTasks.where((t) => t.status.isOpen);
            return open.isNotEmpty && open.every((t) => t.waiting);
          },
        );
        // Status bar text follows the theme: dark on light, light on dark
        // (iOS and Android both read this).
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
          child: UndoKeys(
            onUndo: _undo,
            onRedo: _redo,
            child: Scaffold(
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    ListenableBuilder(
                      listenable: _selection,
                      builder: (context, _) => _TopBar(
                        picking: !_selection.isEmpty,
                        narrow: narrow,
                        title: widget.session == null
                            ? null
                            : ValueListenableBuilder<RemoteCheck?>(
                                valueListenable:
                                    widget.remote ??
                                    ValueNotifier<RemoteCheck?>(null),
                                builder: (context, remote, _) => DocumentMenu(
                                  session: widget.session!,
                                  picker: widget.picker,
                                  remote: remote,
                                ),
                              ),
                        actions: selectionBar,
                        undo: switch (_history) {
                          final h? => UndoButtons(
                            history: h,
                            onUndo: _undo,
                            onRedo: _redo,
                          ),
                          null => null,
                        },
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _view.index,
                        sizing: StackFit.expand,
                        children: [
                          for (final v in AppView.values) _viewFor(v, layout),
                        ],
                      ),
                    ),
                    _timerBar(),
                  ],
                ),
              ),
              bottomNavigationBar: _BottomBar(
                child: ViewSwitcher(
                  key: const Key('view-switch'),
                  current: _view,
                  onSelect: _select,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    this.title,
    required this.actions,
    this.picking = false,
    this.narrow = false,
    this.undo,
  });

  /// ↶ ↷ beside the document's menu, picking or not.
  final Widget? undo;

  /// Something is picked: the actions show (only then; with nothing picked
  /// every one of them would do nothing).
  final bool picking;

  /// A phone held upright: while picking, the actions take the document
  /// name's place.
  final bool narrow;

  /// The document's name and file menu, after the app name.
  final Widget? title;

  /// The picked-task actions: they take the room left and shrink to icons.
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _row(),
        ),
      ),
    );
  }

  Widget _row() => Row(
    children: [
      const Text(
        'Anisched',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 10),
      if (title != null && !(picking && narrow)) Flexible(child: title!),
      ?undo,
      const SizedBox(width: 10),
      Expanded(
        child: picking
            ? Align(alignment: Alignment.centerRight, child: actions)
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(height: 44, child: child),
        ),
      ),
    );
  }
}

/// Row of view buttons sharing the full width. The current one is marked
/// by its fill colour only.
class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final AppView current;
  final ValueChanged<AppView> onSelect;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final v in AppView.values)
        _ViewButton(
          key: Key('view-tab-${v.name}'),
          view: v,
          selected: v == current,
          onTap: () => onSelect(v),
        ),
    ];
    return Row(
      spacing: 4,
      children: [for (final b in buttons) Expanded(child: b)],
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    super.key,
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final AppView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: c.hover,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                widthFactor: 1,
                child: FitText(
                  view.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? ink : c.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
