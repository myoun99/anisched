import 'package:flutter/material.dart';

import '../instant.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../theme.dart';
import '../part_line.dart';
import '../selection.dart';
import '../widgets.dart';
import '../text/strings.dart';

/// One line per part × stage: name, progress and one date signal. Everything
/// else (dates, plan, pace, pay, time, cuts) opens under the line on demand.
/// Done work is hidden unless asked for.
class SheetView extends StatefulWidget {
  const SheetView({
    super.key,
    required this.parts,
    required this.now,
    required this.layout,
    this.dayStartMinutes = 0,
    this.paceOf,
    this.showDone,
    this.onShowDoneChanged,
    this.signals = const {},
    this.paces = const {},
    this.selection,
    this.toolbar,
    this.onReorder,
    this.onTaskTap,
    this.onDue,
    this.onTaskDue,
    this.onHold,
    this.revisionsOf,
    this.onEditRevision,
  });

  /// Sets a unit's deadline / one cut's own deadline.
  final void Function(PartGroup group, DateTime due)? onDue;
  final void Function(TaskRow task, DateTime due)? onTaskDue;

  /// Puts a whole unit on hold, or takes it off.
  final void Function(PartGroup group)? onHold;

  /// A unit's deadline rounds; null hides the list.
  final Future<List<DueRevision>> Function(PartGroup group)? revisionsOf;

  /// Corrects one round of a unit's deadline.
  final void Function(PartGroup group, int revision, DateTime due)?
  onEditRevision;

  /// A cut tapped in the opened details (starts the timer, or picks it
  /// while picking); null: taps pick.
  final ValueChanged<TaskRow>? onTaskTap;

  /// Units to list. With [onReorder] they are shown as given (already
  /// filtered and in the user's order); without it this view filters by
  /// work and sorts by deadline itself.
  final List<PartGroup> parts;

  /// Replaces the view's own toolbar controls (the shell's sort and
  /// filter buttons).
  final List<Widget>? toolbar;

  /// Turns on the rows' drag grips; gets the shown keys in their new order.
  final ValueChanged<List<String>>? onReorder;

  /// The instant deadlines count from.
  final DateTime now;
  final ScreenLayout layout;

  /// When a working day starts (the user's setting).
  final int dayStartMinutes;

  /// The group's pace, shown when a line opens.
  final Pace? Function(PartGroup group)? paceOf;

  /// Whether done work is listed, when the caller owns that choice (it
  /// then reloads [parts] with or without done work). Null keeps it here.
  final bool? showDone;
  final ValueChanged<bool>? onShowDoneChanged;

  /// Deadline and plan signals by group key (reader.signals).
  final Map<String, GroupSignals> signals;

  /// Usual speeds by stage name (reader.stagePaces).
  final Map<String, StagePace> paces;

  /// Tasks picked for an action, shared by every view.
  final TaskSelection? selection;

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView> {
  int? _work;
  bool _ownShowDone = false;

  bool get _showDone => widget.showDone ?? _ownShowDone;

  void _setShowDone(bool on) {
    final cb = widget.onShowDoneChanged;
    if (cb != null) {
      cb(on);
    } else {
      setState(() => _ownShowDone = on);
    }
  }

  final _expanded = <String>{};
  String? _selected;
  final _rows = ScrollController();

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  List<PartGroup> get _visible =>
      widget.onReorder != null
            ? widget.parts
            : [
                for (final p in widget.parts)
                  if ((_showDone || p.status != TaskStatus.done) &&
                      (_work == null || p.workId == _work))
                    p,
              ]
        ..sort(
          (a, b) =>
              (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999)),
        );

  void _toggle(PartGroup p) => setState(() {
    _selected = p.key;
    if (!_expanded.remove(p.key)) _expanded.add(p.key);
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final parts = _visible;
    final narrow = widget.layout.size == SizeClass.narrow;
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ViewToolbar(
            children:
                widget.toolbar ??
                [
                  _workMenu(),
                  ToolbarButton(
                    key: const Key('toggle-done'),
                    label: _showDone ? S.doneShown.t : S.doneHidden.t,
                    selected: _showDone,
                    onTap: () => _setShowDone(!_showDone),
                  ),
                ],
          ),
          if (!narrow) const PartHeader(),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.selection ?? const _Never(),
              builder: (context, _) => _list(parts, (context, i) {
                final p = parts[i];
                final sel = widget.selection;
                final open = _expanded.contains(p.key);
                final body = Column(
                  key: ValueKey(p.key),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PartLine(
                      group: p,
                      now: widget.now,
                      dayStartMinutes: widget.dayStartMinutes,
                      expanded: open,
                      selected: _selected == p.key,
                      signals: widget.signals[p.key],
                      picked: sel?.of(p) ?? Picked.none,
                      onDue: widget.onDue == null
                          ? null
                          : (d) => widget.onDue!(p, d),
                      onLongPress: sel == null
                          ? null
                          : () => sel.toggleGroup(p),
                      onTap: () => sel != null && !sel.isEmpty
                          ? sel.toggleGroup(p)
                          : _toggle(p),
                    ),
                    if (open)
                      PartDetails(
                        group: p,
                        pace:
                            widget.signals[p.key]?.pace ??
                            widget.paceOf?.call(p),
                        plan: widget.signals[p.key]?.plan,
                        usual: widget.paces[p.stageName],
                        isPicked: sel?.has,
                        onTask: widget.onTaskTap ?? sel?.toggleTask,
                        onDue: widget.onDue == null
                            ? null
                            : (d) => widget.onDue!(p, d),
                        onTaskDue: widget.onTaskDue,
                        onHold: widget.onHold == null
                            ? null
                            : () => widget.onHold!(p),
                        loadRevisions:
                            widget.revisionsOf == null ||
                                p.kind == GroupKind.noPart
                            ? null
                            : () => widget.revisionsOf!(p),
                        onEditRevision: widget.onEditRevision == null
                            ? null
                            : (n, d) => widget.onEditRevision!(p, n, d),
                      ),
                  ],
                );
                if (widget.onReorder == null) return body;
                return Row(
                  key: ValueKey(p.key),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: SizedBox(
                          key: Key('grip-${p.key}'),
                          width: 22,
                          height: 52,
                          child: Icon(
                            Icons.drag_indicator,
                            size: 16,
                            color: c.faint,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: body),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<PartGroup> parts, IndexedWidgetBuilder item) {
    final reorder = widget.onReorder;
    if (reorder == null) {
      return ListView.builder(
        key: const Key('sheet-rows'),
        controller: _rows,
        itemCount: parts.length,
        itemBuilder: item,
      );
    }
    return ReorderableListView.builder(
      key: const Key('sheet-rows'),
      scrollController: _rows,
      buildDefaultDragHandles: false,
      itemCount: parts.length,
      itemBuilder: item,
      onReorderItem: (from, to) {
        final keys = [for (final p in parts) p.key];
        keys.insert(to, keys.removeAt(from));
        reorder(keys);
      },
    );
  }

  Widget _workMenu() {
    final works = <int, String>{
      for (final p in widget.parts) p.workId: p.workTitle,
    };
    return PopupMenuButton<int?>(
      key: const Key('work-menu'),
      tooltip: '',
      popUpAnimationStyle: instant,
      onSelected: (w) => setState(() => _work = w),
      itemBuilder: (_) => [
        PopupMenuItem(child: Text(S.allTitles.t)),
        for (final e in works.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: ToolbarButton(
        label: _work == null ? S.allTitles.t : works[_work]!,
        selected: _work != null,
        dropdown: true,
      ),
    );
  }
}

/// A listenable that never fires, for views used without a selection.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
