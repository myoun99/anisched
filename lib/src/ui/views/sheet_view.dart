import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

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
  });

  final List<PartGroup> parts;

  /// The instant deadlines count from.
  final DateTime now;
  final ScreenLayout layout;

  /// When a working day starts (the user's setting).
  final int dayStartMinutes;

  /// The group's pace, shown when a line opens.
  final Pace? Function(PartGroup group)? paceOf;

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView> {
  int? _work;
  bool _showDone = false;
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
                onTap: () => setState(() => _showDone = !_showDone),
              ),
            ],
          ),
          if (!narrow) const _Header(),
          Expanded(
            child: ListView.builder(
              key: const Key('sheet-rows'),
              controller: _rows,
              itemCount: parts.length,
              itemBuilder: (context, i) {
                final p = parts[i];
                final open = _expanded.contains(p.key);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Line(
                      group: p,
                      now: widget.now,
                      dayStartMinutes: widget.dayStartMinutes,
                      expanded: open,
                      selected: _selected == p.key,
                      onTap: () => _toggle(p),
                    ),
                    if (open) _Details(group: p, pace: widget.paceOf?.call(p)),
                  ],
                );
              },
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

const _caretW = 32.0;
const _progressW = 96.0;
const _signalW = 84.0;
const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextStyle(fontSize: 12, color: c.muted);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            const SizedBox(width: _caretW),
            Expanded(child: Text('파트', style: style)),
            SizedBox(
              width: _progressW,
              child: Text('진행', style: style),
            ),
            SizedBox(
              width: _signalW,
              child: Text('마감', style: style, textAlign: TextAlign.right),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

/// Name, progress and the date signal for one group. Tapping opens it.
class _Line extends StatelessWidget {
  const _Line({
    required this.group,
    required this.now,
    required this.dayStartMinutes,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final PartGroup group;
  final DateTime now;
  final int dayStartMinutes;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    return Material(
      color: selected ? c.selected : c.panel,
      child: InkWell(
        key: Key('line-${g.key}'),
        onTap: onTap,
        hoverColor: c.hover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            height: 52,
            child: DefaultTextStyle.merge(
              style: _tabular,
              child: Row(
                children: [
                  SizedBox(
                    width: _caretW,
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: c.muted,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: groupTitle(g),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: '  ${g.stageName}',
                                style: TextStyle(color: c.muted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${g.workTitle} ${g.episodeNumber}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _progressW,
                    child: Row(
                      spacing: 6,
                      children: [
                        SizedBox(width: 44, child: PartProgress(g, height: 4)),
                        Text(
                          '${g.handed}/${g.total}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _signalW,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: DueText(
                        g.dueAt,
                        g.status,
                        now,
                        dayStartMinutes: dayStartMinutes,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What opens under a line: dates, plan, pace, pay, time and the cuts.
class _Details extends StatelessWidget {
  const _Details({required this.group, this.pace});

  final PartGroup group;
  final Pace? pace;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final accent = Theme.of(context).colorScheme.primary;
    final slack = g.slackDays;
    final perDay = pace?.perDay;
    final plan = g.planStartAt == null
        ? '—'
        : '${formatDate(g.planStartAt)} – '
              '${g.planEndAt == null ? '마감' : formatDate(g.planEndAt)}';
    final facts = <(String, String)>[
      ('마감', formatDate(g.dueAt)),
      ('내 계획', plan),
      ('여유', slack == null ? '—' : '$slack일'),
      ('하루', perDay == null ? '—' : '${perDay.toStringAsFixed(1)}컷'),
      ('단가', formatMoney(g.currency, g.pay)),
      ('시간', formatWorked(g.worked)),
    ];
    return DecoratedBox(
      key: Key('details-${g.key}'),
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_caretW, 10, 14, 12),
        child: DefaultTextStyle.merge(
          style: _tabular,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  for (final (k, v) in facts)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Text(k, style: TextStyle(fontSize: 12, color: c.muted)),
                        Text(v),
                      ],
                    ),
                ],
              ),
              if (g.kind != GroupKind.storyboard)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final t in g.tasks)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.panel,
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 6,
                            children: [
                              Dot(c.of(t.status)),
                              Text(
                                taskLabel(t),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TakeBadge(t.take),
                              Text(
                                formatLength(t.lengthMs),
                                style: TextStyle(color: c.muted),
                              ),
                              if (t.dueOverridden)
                                Text(
                                  formatDate(t.dueAt),
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
