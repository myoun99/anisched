import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../theme.dart';
import '../part_line.dart';
import '../selection.dart';

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
  });

  final List<PartGroup> parts;

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
      [
        for (final p in widget.parts)
          if ((_showDone || p.status != TaskStatus.done) &&
              (_work == null || p.workId == _work))
            p,
      ]..sort(
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
          _Toolbar(
            children: [
              _workMenu(),
              _MenuButton(
                key: const Key('toggle-done'),
                label: _showDone ? '완료 보임' : '완료 숨김',
                selected: _showDone,
                onTap: () => _setShowDone(!_showDone),
              ),
            ],
          ),
          if (!narrow) const PartHeader(),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.selection ?? const _Never(),
              builder: (context, _) => ListView.builder(
                key: const Key('sheet-rows'),
                controller: _rows,
                itemCount: parts.length,
                itemBuilder: (context, i) {
                  final p = parts[i];
                  final sel = widget.selection;
                  final open = _expanded.contains(p.key);
                  return Column(
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
                          onTask: sel?.toggleTask,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workMenu() {
    final works = <int, String>{
      for (final p in widget.parts) p.workId: p.workTitle,
    };
    return PopupMenuButton<int?>(
      key: const Key('work-menu'),
      tooltip: '',
      onSelected: (w) => setState(() => _work = w),
      itemBuilder: (_) => [
        const PopupMenuItem(child: Text('모든 작품')),
        for (final e in works.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: _MenuButton(
        label: _work == null ? '모든 작품' : works[_work]!,
        selected: _work != null,
        dropdown: true,
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.dropdown = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Shows a drop-down arrow after the label.
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? c.selected : c.panel,
        border: Border.all(color: selected ? c.selected : c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (dropdown)
                Icon(Icons.arrow_drop_down, size: 20, color: c.muted),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: body,
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
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
