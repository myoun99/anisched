import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/registration.dart';
import '../core/clock.dart';
import '../core/size_class.dart';
import '../models/lanes.dart';
import '../models/progress.dart';
import '../models/catalogue.dart';
import '../services/catalogue_reader.dart';
import '../services/catalogue_store.dart';
import '../services/document_session.dart';
import '../services/work_timer.dart';
import 'document_menu.dart';
import 'filter.dart';
import 'selection.dart';
import 'selection_bar.dart';
import 'theme.dart';
import 'timer_bar.dart';
import 'widgets.dart';
import 'views/register_view.dart';
import 'views/settings_view.dart';
import 'views/sheet_view.dart';
import 'views/timeline_view.dart';
import 'views/work_view.dart';

/// The app's views: the list, the production timeline, the user's own
/// work on parallel lanes, registration and settings.
enum AppView {
  list('목록'),
  timeline('타임라인'),
  work('작업'),
  register('등록'),
  settings('설정');

  const AppView(this.label);

  final String label;
}

/// App frame: a top bar, the current view, and the view switcher — in the
/// top bar on medium and wide screens, along the bottom on narrow ones.
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
  });

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
  final DocumentSession? session;
  final DocumentPicker picker;

  /// The last resume check, for the save-state icon.
  final ValueListenable<RemoteCheck?>? remote;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppView _view = widget.initialView;
  List<PartGroup> _groups = const [];
  Map<String, GroupSignals> _signals = const {};
  Map<String, StagePace> _paces = const {};
  LaneLayout? _lanes;
  ViewFilter _filter = const ViewFilter();
  Map<int, ({String title, int? clientId})> _works = const {};
  Map<int, String> _clients = const {};
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
    _doc = widget.session?.changes.listen(_onDocument);
    unawaited(_loadGroups());
  }

  /// Reloads the sheet's groups; the last ones stay on screen meanwhile.
  Future<void> _loadGroups() async {
    final reader = widget.reader;
    if (reader == null) return;
    final done = _filter.showDone;
    final (groups, signals, paces, lanes, works, clients, roles) = await (
      reader.partGroups(includeDone: done),
      reader.signals(includeDone: done),
      reader.stagePaces(),
      reader.calendarLayout(basis: CalendarBasis.work),
      reader.works(),
      reader.clients(),
      reader.roles(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _works = {
        for (final w in works) w.id: (title: w.title, clientId: w.clientId),
      };
      _clients = {for (final c in clients) c.id: c.name};
      _roles = roles;
      _groups = groups;
      _signals = signals;
      _paces = {for (final p in paces) p.stageName: p};
      _lanes = lanes.layout;
    });
  }

  /// The task the timer last ran on, for resume.
  int? _timerTask;

  Widget _timerBar() {
    final timer = widget.timer;
    final running = timer?.running();
    final id = running?.taskId ?? _timerTask;
    TaskRow? task;
    PartGroup? group;
    for (final g in _groups) {
      for (final t in g.tasks) {
        if (t.id == id) {
          task = t;
          group = g;
        }
      }
    }
    return TimerBar(
      running: running,
      task: task,
      group: group,
      clock: widget.clock,
      onStop: timer == null
          ? null
          : () {
              timer.stop();
              setState(() {});
            },
      onResume: timer == null || id == null ? null : () => _startTimer(id),
    );
  }

  /// Starts the timer on a task (stopping any other first).
  void _startTimer(int taskId) {
    final timer = widget.timer;
    if (timer == null) return;
    timer
      ..stop()
      ..start(taskId: taskId);
    setState(() => _timerTask = taskId);
  }

  /// Runs one write on the store, then reloads every view.
  void _write(void Function(CatalogueStore store) body) {
    final store = widget.store;
    if (store == null) return;
    body(store);
    setState(() => _refresh++);
    unawaited(_loadGroups());
  }

  void _setFilter(ViewFilter f) {
    final reload = f.showDone != _filter.showDone;
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

  List<Widget> _toolbar(int count) => [
    ToolbarButton(
      key: const Key('sort-by-due'),
      label: '마감 순 정렬',
      selected: false,
      onTap: widget.store == null
          ? null
          : () => _write((s) => s.clearGroupOrder()),
    ),
    FilterButton(
      filter: _filter,
      onChanged: _setFilter,
      clients: _clients,
      works: {
        for (final w in _works.entries)
          if (_groups.any((g) => g.workId == w.key)) w.key: w.value.title,
      },
    ),
    SizedBox(
      height: 34,
      child: Center(
        child: Text(
          '$count건',
          style: TextStyle(color: AppColors.of(context).muted),
        ),
      ),
    ),
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

  /// A work bar's end dragged: the user's own start and end.
  void _plan(PartGroup g, DateTime start, DateTime end) => _write((store) {
    final a = _startOf(start);
    final b = _endOf(end);
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
    final now = widget.clock();
    final rest =
        widget.store?.settings.restWeekdays ??
        const {DateTime.saturday, DateTime.sunday};
    final writable = widget.store != null;
    final shown = _visible(now);
    final toolbar = _toolbar(shown.length);
    return switch (v) {
      AppView.list => SheetView(
        parts: shown,
        now: now,
        layout: layout,
        showDone: _filter.showDone,
        signals: _signals,
        paces: _paces,
        selection: _selection,
        toolbar: toolbar,
        onReorder: writable ? _reorder : null,
        onTaskTap: widget.timer == null
            ? null
            : (t) => _selection.isEmpty
                  ? _startTimer(t.id)
                  : _selection.toggleTask(t),
      ),
      AppView.timeline => TimelineView(
        parts: shown,
        toolbar: toolbar,
        onReorder: writable ? _reorder : null,
        now: now,
        layout: layout,
        restWeekdays: rest,
        selection: _selection,
        onSchedule: writable ? _schedule : null,
      ),
      AppView.work => WorkView(
        lanes: _lanes,
        parts: {for (final g in _groups) g.key: g},
        now: now,
        layout: layout,
        restWeekdays: rest,
        onPin: writable
            ? (key, lane) => _write((s) => s.pinLane(key, lane))
            : null,
        onClearPins: writable ? () => _write((s) => s.clearLanePins()) : null,
        onPlan: writable ? _plan : null,
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
            ? (work, number) {
                var id = 0;
                _write((s) => id = s.addEpisode(work, number));
                return id;
              }
            : null,
        onEdit: writable ? _write : null,
        onRegister: writable
            ? (draft) {
                var n = 0;
                _write((s) => n = register(s, draft).length);
                return n;
              }
            : null,
      ),
      AppView.settings => SettingsView(
        now: now,
        session: widget.session,
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
        final wide = layout.size == SizeClass.wide;
        final selectionBar = SelectionBar(
          selection: _selection,
          onApply: widget.store == null ? null : _apply,
        );
        final switcher = ViewSwitcher(
          key: Key(narrow ? 'view-switch-bottom' : 'view-switch-top'),
          current: _view,
          onSelect: _select,
          expand: narrow,
        );
        return Scaffold(
          body: SafeArea(
            bottom: !narrow,
            child: Column(
              children: [
                _TopBar(
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [if (wide) selectionBar, if (!narrow) switcher],
                  ),
                ),
                // Below wide screens the picked-task actions get a row of
                // their own, always there, so nothing shifts or overlaps.
                if (!wide) _SelectionRow(child: selectionBar),
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
          bottomNavigationBar: narrow ? _BottomBar(child: switcher) : null,
        );
      },
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      key: const Key('selection-row'),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 46,
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.title, this.trailing});

  /// The document's name and file menu, after the app name.
  final Widget? title;
  final Widget? trailing;

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
          child: Row(
            children: [
              const Text(
                'Anisched',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              ?title,
              const SizedBox(width: 12),
              if (trailing != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: trailing,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

/// Row of view buttons. The current one is marked by its fill colour only.
class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({
    super.key,
    required this.current,
    required this.onSelect,
    this.expand = false,
  });

  final AppView current;
  final ValueChanged<AppView> onSelect;

  /// Stretch the buttons to share the full width (bottom bar).
  final bool expand;

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
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      spacing: 4,
      children: [
        for (final b in buttons)
          if (expand) Expanded(child: b) else b,
      ],
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    view.label,
                    maxLines: 1,
                    softWrap: false,
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
      ),
    );
  }
}
