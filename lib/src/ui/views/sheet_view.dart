import 'package:flutter/material.dart';

import '../instant.dart';

import '../../controllers/unit_bundles.dart';
import '../../core/size_class.dart';
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
    this.wiring = const UnitWiring(),
    this.showDone,
    this.onShowDoneChanged,
    this.toolbar,
    this.onReorder,
  });

  /// What the lines and their opened details act through (the shell's).
  final UnitWiring wiring;

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

  /// Whether done work is listed, when the caller owns that choice (it
  /// then reloads [parts] with or without done work). Null keeps it here.
  final bool? showDone;
  final ValueChanged<bool>? onShowDoneChanged;

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
                  if ((_showDone || !p.status.isHanded) &&
                      (_work == null || p.workId == _work))
                    p,
              ]
        ..sort(
          (a, b) =>
              (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999)),
        );

  void _toggle(String key) => setState(() {
    _selected = key;
    if (!_expanded.remove(key)) _expanded.add(key);
  });

  /// One unit's line, and its details when open.
  Widget _unit(PartGroup p, {UnitBundle? bundle}) {
    final sel = widget.wiring.selection;
    final key = bundle?.key ?? p.key;
    final open = _expanded.contains(key);
    final whole = bundle?.together ?? p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartLine(
          group: p,
          bundle: bundle,
          client: widget.wiring.clientOf?.call(p),
          now: widget.now,
          dayStartMinutes: widget.dayStartMinutes,
          expanded: open,
          selected: _selected == key,
          signals: widget.wiring.signals[p.key],
          picked: sel?.of(whole) ?? Picked.none,
          onDue: widget.wiring.onDue == null
              ? null
              : (d) => widget.wiring.onDue!(p, d),
          onLongPress: sel == null ? null : () => sel.toggleGroup(whole),
          onTap: () => sel != null && !sel.isEmpty
              ? sel.toggleGroup(whole)
              : _toggle(key),
        ),
        if (open && bundle == null) widget.wiring.details(p),
        // An open bundle lists its stages, each opening on its own.
        if (open && bundle != null)
          for (final s in bundle.stages)
            Padding(padding: const EdgeInsets.only(left: 16), child: _unit(s)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bundles = bundleUnits(_visible);
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
              listenable: widget.wiring.selection ?? const _Never(),
              builder: (context, _) => _list(bundles, (context, i) {
                final b = bundles[i];
                final body = KeyedSubtree(
                  key: ValueKey(b.key),
                  child: b.single ? _unit(b.lead) : _unit(b.lead, bundle: b),
                );
                if (widget.onReorder == null) return body;
                return Row(
                  key: ValueKey(b.key),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: SizedBox(
                          key: Key('grip-${b.key}'),
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

  Widget _list(List<UnitBundle> parts, IndexedWidgetBuilder item) {
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
        // A bundle moves all its stages together.
        final moved = [...parts];
        moved.insert(to, moved.removeAt(from));
        reorder([
          for (final b in moved)
            for (final s in b.stages) s.key,
        ]);
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
