import 'dart:async';

import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../core/size_class.dart';
import '../models/lanes.dart';
import '../models/progress.dart';
import '../models/catalogue.dart';
import '../services/catalogue_reader.dart';
import '../services/catalogue_store.dart';
import '../services/work_timer.dart';
import 'selection.dart';
import 'selection_bar.dart';
import 'theme.dart';
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppView _view = widget.initialView;
  List<PartGroup> _groups = const [];
  Map<String, GroupSignals> _signals = const {};
  Map<String, StagePace> _paces = const {};
  LaneLayout? _lanes;
  bool _showDone = false;
  final _selection = TaskSelection();
  int _refresh = 0;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
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
    unawaited(_loadGroups());
  }

  /// Reloads the sheet's groups; the last ones stay on screen meanwhile.
  Future<void> _loadGroups() async {
    final reader = widget.reader;
    if (reader == null) return;
    final done = _showDone;
    final (groups, signals, paces, lanes) = await (
      reader.partGroups(includeDone: done),
      reader.signals(includeDone: done),
      reader.stagePaces(),
      reader.calendarLayout(basis: CalendarBasis.work),
    ).wait;
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _signals = signals;
      _paces = {for (final p in paces) p.stageName: p};
      _lanes = lanes.layout;
    });
  }

  /// Runs one write on the store, then reloads every view.
  void _write(void Function(CatalogueStore store) body) {
    final store = widget.store;
    if (store == null) return;
    body(store);
    setState(() => _refresh++);
    unawaited(_loadGroups());
  }

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
    void showDone(bool on) {
      setState(() => _showDone = on);
      unawaited(_loadGroups());
    }

    return switch (v) {
      AppView.list => SheetView(
        parts: _groups,
        now: now,
        layout: layout,
        showDone: _showDone,
        signals: _signals,
        paces: _paces,
        selection: _selection,
        onShowDoneChanged: showDone,
      ),
      AppView.timeline => TimelineView(
        parts: _groups,
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
      AppView.register || AppView.settings => ViewSlot(view: v, layout: layout),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      SelectionBar(
                        selection: _selection,
                        onApply: widget.store == null ? null : _apply,
                      ),
                      if (!narrow) switcher,
                    ],
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
              ],
            ),
          ),
          bottomNavigationBar: narrow ? _BottomBar(child: switcher) : null,
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.trailing});

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
              const SizedBox(width: 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  view.label,
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

/// Space reserved for one view until it is built from the data lane's
/// models. It shows only the view's name.
class ViewSlot extends StatelessWidget {
  const ViewSlot({super.key, required this.view, required this.layout});

  final AppView view;
  final ScreenLayout layout;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ColoredBox(
      color: c.panelAlt,
      child: Center(
        child: Text(view.label, style: TextStyle(fontSize: 20, color: c.faint)),
      ),
    );
  }
}
