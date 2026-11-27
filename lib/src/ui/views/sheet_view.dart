import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Columns the sheet can sort by.
enum SheetSort { name, stage, count, progress, status, due, pay, worked }

/// Dense table of part × stage rows; a part opens to show its tasks.
/// Wide screens show every column, medium drop the progress column, and
/// narrow screens switch to two-line rows.
class SheetView extends StatefulWidget {
  const SheetView({
    super.key,
    required this.parts,
    required this.now,
    required this.layout,
    this.dayStartMinutes = 0,
  });

  final List<PartGroup> parts;

  /// The instant deadlines count from.
  final DateTime now;
  final ScreenLayout layout;

  /// When a working day starts (the user's setting).
  final int dayStartMinutes;

  @override
  State<SheetView> createState() => _SheetViewState();
}

sealed class _Row {}

class _PartRow extends _Row {
  _PartRow(this.part);
  final PartGroup part;
}

class _TaskRow extends _Row {
  _TaskRow(this.part, this.task);
  final PartGroup part;
  final TaskRow task;
}

class _SheetViewState extends State<SheetView> {
  TaskStatus? _status;
  String? _work;
  SheetSort _sort = SheetSort.due;
  bool _ascending = true;
  final _expanded = <String>{};
  String? _selectedPart;
  int? _selectedTask;
  final _rows = ScrollController();

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  List<PartGroup> get _visible {
    final list = [
      for (final p in widget.parts)
        if ((_status == null || p.status == _status) &&
            (_work == null || p.workTitle == _work))
          p,
    ]..sort(_compare);
    return _ascending ? list : list.reversed.toList();
  }

  int _compare(PartGroup a, PartGroup b) {
    int byDue() =>
        (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
    final r = switch (_sort) {
      SheetSort.name => '${a.workTitle}${a.episodeNumber}${a.label}'.compareTo(
        '${b.workTitle}${b.episodeNumber}${b.label}',
      ),
      SheetSort.stage => a.stageName.compareTo(b.stageName),
      SheetSort.count => a.total.compareTo(b.total),
      SheetSort.progress => (a.handed / a.total).compareTo(b.handed / b.total),
      SheetSort.status => a.status.urgency.compareTo(b.status.urgency),
      SheetSort.due => byDue(),
      SheetSort.pay => a.pay.compareTo(b.pay),
      SheetSort.worked => a.worked.compareTo(b.worked),
    };
    return r != 0 ? r : byDue();
  }

  void _sortBy(SheetSort s) => setState(() {
    if (_sort == s) {
      _ascending = !_ascending;
    } else {
      _sort = s;
      _ascending = true;
    }
  });

  void _toggle(PartGroup p) => setState(() {
    if (!_expanded.remove(p.key)) _expanded.add(p.key);
  });

  void _selectPart(PartGroup p) => setState(() {
    _selectedPart = p.key;
    _selectedTask = null;
  });

  void _selectTask(PartGroup p, TaskRow t) => setState(() {
    _selectedPart = p.key;
    _selectedTask = t.id;
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final parts = _visible;
    final rows = <_Row>[
      for (final p in parts) ...[
        _PartRow(p),
        if (_expanded.contains(p.key) && !p.solo)
          for (final t in p.tasks) _TaskRow(p, t),
      ],
    ];
    final narrow = widget.layout.size == SizeClass.narrow;
    final cols = _Columns.forLayout(widget.layout.size);
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(children: [_statusFilter(), _workFilter()]),
          if (narrow)
            _Toolbar(children: [_sortFilter()])
          else
            _HeaderRow(
              columns: cols,
              sort: _sort,
              ascending: _ascending,
              onSort: _sortBy,
            ),
          Expanded(
            child: ListView.builder(
              key: const Key('sheet-rows'),
              controller: _rows,
              itemCount: rows.length,
              itemBuilder: (context, i) => switch (rows[i]) {
                _PartRow(:final part) =>
                  narrow
                      ? _NarrowPartTile(
                          part: part,
                          now: widget.now,
                          dayStartMinutes: widget.dayStartMinutes,
                          expanded: _expanded.contains(part.key),
                          selected: _selectedPart == part.key,
                          onTap: () => _selectPart(part),
                          onToggle: () => _toggle(part),
                        )
                      : _PartLine(
                          part: part,
                          columns: cols,
                          now: widget.now,
                          dayStartMinutes: widget.dayStartMinutes,
                          expanded: _expanded.contains(part.key),
                          selected:
                              _selectedPart == part.key &&
                              _selectedTask == null,
                          onTap: () => _selectPart(part),
                          onToggle: () => _toggle(part),
                        ),
                _TaskRow(:final part, :final task) => _TaskLine(
                  part: part,
                  task: task,
                  columns: narrow ? null : cols,
                  now: widget.now,
                  dayStartMinutes: widget.dayStartMinutes,
                  selected: _selectedTask == task.id,
                  onTap: () => _selectTask(part, task),
                ),
              },
            ),
          ),
          _Footer(parts: parts),
        ],
      ),
    );
  }

  Widget _statusFilter() {
    final c = AppColors.of(context);
    return SegmentGroup(
      children: [
        SegmentButton(
          label: '전체',
          count: widget.parts.length,
          selected: _status == null,
          onTap: () => setState(() => _status = null),
        ),
        for (final s in TaskStatus.values)
          SegmentButton(
            label: s.label,
            dot: c.of(s),
            count: widget.parts.where((p) => p.status == s).length,
            selected: _status == s,
            onTap: () => setState(() => _status = s),
          ),
      ],
    );
  }

  Widget _workFilter() {
    final works = {for (final p in widget.parts) p.workTitle};
    return SegmentGroup(
      children: [
        SegmentButton(
          label: '전체',
          selected: _work == null,
          onTap: () => setState(() => _work = null),
        ),
        for (final w in works)
          SegmentButton(
            label: w,
            selected: _work == w,
            onTap: () => setState(() => _work = w),
          ),
      ],
    );
  }

  Widget _sortFilter() => SegmentGroup(
    children: [
      for (final (s, l) in const [
        (SheetSort.due, '마감'),
        (SheetSort.status, '상태'),
        (SheetSort.name, '작품'),
      ])
        SegmentButton(
          label: _sort == s ? '$l ${_ascending ? '↑' : '↓'}' : l,
          selected: _sort == s,
          onTap: () => _sortBy(s),
        ),
    ],
  );
}

class _Toolbar extends StatefulWidget {
  const _Toolbar({required this.children});

  final List<Widget> children;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 58,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
          child: Row(spacing: 8, children: widget.children),
        ),
      ),
    );
  }
}

/// Column widths for wide and medium sheets; null fields are hidden.
class _Columns {
  const _Columns({this.progress});

  factory _Columns.forLayout(SizeClass s) =>
      s == SizeClass.wide ? const _Columns(progress: 130) : const _Columns();

  static const stage = 120.0;
  static const count = 74.0;
  static const status = 84.0;
  static const due = 108.0;
  static const dday = 72.0;
  static const pay = 110.0;
  static const worked = 76.0;
  final double? progress;
}

const _hPad = EdgeInsets.symmetric(horizontal: 10);
const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final _Columns columns;
  final SheetSort sort;
  final bool ascending;
  final ValueChanged<SheetSort> onSort;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget cell(
      SheetSort s,
      String label, {
      double? width,
      bool end = false,
      bool showArrow = true,
    }) {
      final arrow = showArrow && sort == s ? (ascending ? ' ↑' : ' ↓') : '';
      final child = InkWell(
        onTap: () => onSort(s),
        child: Padding(
          padding: _hPad,
          child: Align(
            alignment: end ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              '$label$arrow',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
        ),
      );
      return width == null
          ? Expanded(child: child)
          : SizedBox(width: width, child: child);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            cell(SheetSort.name, '파트 · 작품'),
            cell(SheetSort.stage, '공정', width: _Columns.stage),
            cell(SheetSort.count, '컷', width: _Columns.count),
            if (columns.progress != null)
              cell(SheetSort.progress, '진행', width: columns.progress),
            cell(SheetSort.status, '상태', width: _Columns.status),
            cell(SheetSort.due, '마감', width: _Columns.due),
            cell(SheetSort.due, 'D', width: _Columns.dday, showArrow: false),
            cell(SheetSort.pay, '단가', width: _Columns.pay, end: true),
            cell(SheetSort.worked, '시간', width: _Columns.worked, end: true),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Caret that opens or closes a part; an empty slot for single-task parts.
class _Caret extends StatelessWidget {
  const _Caret({required this.part, required this.open, required this.onTap});

  final PartGroup part;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (part.solo) return const SizedBox(width: 28);
    return SizedBox(
      width: 28,
      child: InkWell(
        key: Key('caret-${part.key}'),
        onTap: onTap,
        child: Center(
          child: Icon(
            open ? Icons.expand_more : Icons.chevron_right,
            size: 18,
            color: AppColors.of(context).muted,
          ),
        ),
      ),
    );
  }
}

class _PartLine extends StatelessWidget {
  const _PartLine({
    required this.part,
    required this.columns,
    required this.now,
    required this.dayStartMinutes,
    required this.expanded,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  final PartGroup part;
  final _Columns columns;
  final DateTime now;
  final int dayStartMinutes;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = part;
    Widget box(double w, Widget child, {bool end = false}) => SizedBox(
      width: w,
      child: Padding(
        padding: _hPad,
        child: Align(
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );
    return Material(
      color: selected ? c.selected : c.panelAlt,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            height: 34,
            child: DefaultTextStyle.merge(
              style: _tabular,
              child: Row(
                children: [
                  _Caret(part: p, open: expanded, onTap: onToggle),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${groupTitle(p)}  ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: '${p.workTitle} '),
                          TextSpan(
                            text: p.episodeNumber,
                            style: TextStyle(color: c.muted),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  box(_Columns.stage, Text(p.stageName, maxLines: 1)),
                  box(_Columns.count, Text(groupCount(p))),
                  if (columns.progress != null)
                    box(
                      columns.progress!,
                      Row(
                        spacing: 6,
                        children: [
                          Expanded(child: PartProgress(p)),
                          Text('${p.handed}/${p.total}'),
                        ],
                      ),
                    ),
                  box(_Columns.status, StatusPill(p.status)),
                  box(_Columns.due, Text(formatDate(p.dueAt))),
                  box(
                    _Columns.dday,
                    DueText(
                      p.dueAt,
                      p.status,
                      now,
                      dayStartMinutes: dayStartMinutes,
                    ),
                  ),
                  box(
                    _Columns.pay,
                    Text(formatMoney(p.currency, p.pay)),
                    end: true,
                  ),
                  box(_Columns.worked, Text(formatWorked(p.worked)), end: true),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One task under an open part. With [columns] it lines up with the
/// table; without, it is a compact row for narrow screens.
class _TaskLine extends StatelessWidget {
  const _TaskLine({
    required this.part,
    required this.task,
    required this.columns,
    required this.now,
    required this.dayStartMinutes,
    required this.selected,
    required this.onTap,
  });

  final PartGroup part;
  final TaskRow task;
  final _Columns? columns;
  final DateTime now;
  final int dayStartMinutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = task;
    final dueStyle = !t.dueOverridden
        ? TextStyle(color: c.faint)
        : TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          );
    Widget box(double w, Widget child, {bool end = false}) => SizedBox(
      width: w,
      child: Padding(
        padding: _hPad,
        child: Align(
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );
    final name = Row(
      spacing: 6,
      children: [
        Dot(c.of(t.status)),
        Text(taskLabel(t), style: const TextStyle(fontWeight: FontWeight.w700)),
        TakeBadge(t.take),
      ],
    );
    final cols = columns;
    final Widget row = cols == null
        ? Padding(
            padding: const EdgeInsets.only(left: 40, right: 12),
            child: Row(
              spacing: 10,
              children: [
                name,
                Expanded(
                  child: Text(
                    formatLength(t.lengthMs),
                    style: TextStyle(color: c.muted),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ),
                StatusPill(t.status),
                Text(formatDate(t.dueAt), style: dueStyle),
              ],
            ),
          )
        : Row(
            children: [
              const SizedBox(width: 40),
              Expanded(child: name),
              box(
                _Columns.stage,
                Text(part.stageName, style: TextStyle(color: c.faint)),
              ),
              box(_Columns.count, Text(formatLength(t.lengthMs))),
              if (cols.progress != null) SizedBox(width: cols.progress),
              box(_Columns.status, StatusPill(t.status)),
              box(_Columns.due, Text(formatDate(t.dueAt), style: dueStyle)),
              box(
                _Columns.dday,
                !t.dueOverridden
                    ? const SizedBox.shrink()
                    : DueText(
                        t.dueAt,
                        t.status,
                        now,
                        dayStartMinutes: dayStartMinutes,
                      ),
              ),
              box(
                _Columns.pay,
                Text(t.pay == null ? '미정' : formatMoney(part.currency, t.pay!)),
                end: true,
              ),
              box(_Columns.worked, Text(formatWorked(t.worked)), end: true),
              const SizedBox(width: 12),
            ],
          );
    return Material(
      color: selected ? c.selected : c.panel,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            height: 32,
            child: DefaultTextStyle.merge(style: _tabular, child: row),
          ),
        ),
      ),
    );
  }
}

class _NarrowPartTile extends StatelessWidget {
  const _NarrowPartTile({
    required this.part,
    required this.now,
    required this.dayStartMinutes,
    required this.expanded,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  final PartGroup part;
  final DateTime now;
  final int dayStartMinutes;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = part;
    return Material(
      color: selected ? c.selected : c.panel,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            height: 64,
            child: DefaultTextStyle.merge(
              style: _tabular,
              child: Row(
                children: [
                  _Caret(part: p, open: expanded, onTap: onToggle),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 5,
                      children: [
                        Row(
                          spacing: 8,
                          children: [
                            Text(
                              groupTitle(p),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(p.stageName),
                            Expanded(
                              child: Text(
                                '${p.workTitle} ${p.episodeNumber}',
                                style: TextStyle(color: c.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          spacing: 8,
                          children: [
                            PartProgress(p, width: 56),
                            Flexible(
                              child: Text(
                                '${groupCount(p)} '
                                '${p.handed}/${p.total}'
                                ' · ${formatDate(p.dueAt)}',
                                style: TextStyle(fontSize: 12, color: c.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DueText(
                              p.dueAt,
                              p.status,
                              now,
                              dayStartMinutes: dayStartMinutes,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12, left: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: 5,
                      children: [
                        StatusPill(p.status),
                        Text(
                          formatMoney(p.currency, p.pay),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.parts});

  final List<PartGroup> parts;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final tasks = parts.fold(0, (a, p) => a + p.total);
    final worked = parts.fold(Duration.zero, (a, p) => a + p.worked);
    final totals = totalsByCurrency(parts).entries
        .map((e) => formatMoney(e.key, e.value))
        .join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DefaultTextStyle.merge(
            style: _tabular.copyWith(fontWeight: FontWeight.w700),
            child: Row(
              spacing: 14,
              children: [
                Text('${parts.length}파트 · $tasks건'),
                const Spacer(),
                Flexible(
                  child: Text(
                    totals,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(formatWorked(worked), style: TextStyle(color: c.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
