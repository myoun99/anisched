import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../../services/catalogue_reader.dart';
import '../../services/catalogue_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// The user's settings: rest weekdays, days off, parallel lanes, when a
/// day starts, per-second rounding, usual speeds and this month's pay.
/// Segmented rows share their width evenly.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.now,
    this.store,
    this.reader,
    this.paces = const {},
    this.refresh = 0,
    this.onChanged,
  });

  final DateTime now;

  /// Reads and writes the settings; null shows defaults, read-only.
  final CatalogueStore? store;

  /// For this month's totals.
  final CatalogueReader? reader;

  /// Usual speeds by stage name.
  final Map<String, StagePace> paces;

  /// Bumped by the shell after writes elsewhere; reloads the totals.
  final int refresh;

  /// Called after a setting is written, so the views reload.
  final VoidCallback? onChanged;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  MonthlyTotals _totals = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadTotals());
  }

  @override
  void didUpdateWidget(SettingsView old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) unawaited(_loadTotals());
  }

  Future<void> _loadTotals() async {
    final r = widget.reader;
    if (r == null) return;
    final t = await r.monthlyTotals(widget.now.year, widget.now.month);
    if (mounted) setState(() => _totals = t);
  }

  void _set(void Function(CatalogueStore s) write) {
    final s = widget.store;
    if (s == null) return;
    write(s);
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _addDaysOff() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(widget.now.year - 1),
      lastDate: DateTime(widget.now.year + 2),
    );
    if (r == null || !mounted) return;
    _set((s) => s.addDaysOff(r.start, end: r.end));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = widget.store?.settings;
    final rest = s?.restWeekdays ?? {DateTime.saturday, DateTime.sunday};
    final lanes = s?.parallelLanes ?? 2;
    final dayStart = s?.dayStartMinutes ?? 0;
    final rounding = s?.secondsRounding ?? SecondsRounding.nearest;
    final off = widget.store?.daysOff() ?? const [];
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return ColoredBox(
      color: c.panel,
      child: OwnScroll(
        builder: (controller) => Scrollbar(
          controller: controller,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: [
              _section('쉬는 요일', [
                _FillRow(
                  children: [
                    for (var d = 1; d <= 7; d++)
                      SegmentButton(
                        key: Key('rest-$d'),
                        label: weekdays[d - 1],
                        selected: rest.contains(d),
                        onTap: () => _set(
                          (st) => st.settings.restWeekdays = rest.contains(d)
                              ? (rest.toSet()..remove(d))
                              : (rest.toSet()..add(d)),
                        ),
                      ),
                  ],
                ),
              ]),
              _section('쉬는 날', [
                for (final o in off)
                  _Line(
                    children: [
                      Text(
                        o.range.start == o.range.end
                            ? formatDate(o.range.start)
                            : '${formatDate(o.range.start)} – ${formatDate(o.range.end)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (o.note != null)
                        Text(o.note!, style: TextStyle(color: c.muted)),
                      const Spacer(),
                      ToolbarButton(
                        label: '지우기',
                        selected: false,
                        onTap: () => _set((st) => st.removeDaysOff(o.id)),
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ToolbarButton(
                    key: const Key('days-off-add'),
                    label: '추가',
                    selected: false,
                    onTap: widget.store == null ? null : _addDaysOff,
                  ),
                ),
              ]),
              _section('병행 수', [
                _FillRow(
                  children: [
                    for (var n = 1; n <= 4; n++)
                      SegmentButton(
                        key: Key('lanes-$n'),
                        label: '$n',
                        selected: lanes == n,
                        onTap: () =>
                            _set((st) => st.settings.parallelLanes = n),
                      ),
                  ],
                ),
              ]),
              _section('하루 시작', [
                _FillRow(
                  children: [
                    for (final m in const [0, 240, 360])
                      SegmentButton(
                        label: '${m ~/ 60}:00',
                        selected: dayStart == m,
                        onTap: () =>
                            _set((st) => st.settings.dayStartMinutes = m),
                      ),
                  ],
                ),
              ]),
              _section('초당 단가 반올림', [
                _FillRow(
                  children: [
                    for (final (r, l) in const [
                      (SecondsRounding.nearest, '반올림'),
                      (SecondsRounding.up, '올림'),
                      (SecondsRounding.down, '버림'),
                      (SecondsRounding.exact, '그대로'),
                    ])
                      SegmentButton(
                        label: l,
                        selected: rounding == r,
                        onTap: () =>
                            _set((st) => st.settings.secondsRounding = r),
                      ),
                  ],
                ),
              ]),
              _section('평소 속도 (하루 cut)', [
                for (final p in widget.paces.values)
                  _Line(
                    children: [
                      Text(
                        p.stageName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text.rich(
                        TextSpan(
                          text: '${_one(p.overall.perDay)} · 최근 ',
                          children: [
                            TextSpan(
                              text: _one(p.recent.perDay),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ]),
              _section('이번 달 완료', [
                for (final e in _totals.entries)
                  _Line(
                    children: [
                      Text(
                        formatMoney(e.key, e.value.total),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (e.value.unpriced > 0)
                        Text(
                          '단가 없음 ${e.value.unpriced}',
                          style: TextStyle(color: c.muted),
                        ),
                    ],
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  static String _one(double? v) => v == null
      ? '—'
      : (v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1));

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          ...children,
        ],
      ),
    ),
  );
}

/// Segment buttons sharing the row's width evenly.
class _FillRow extends StatelessWidget {
  const _FillRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, color: c.line),
                Expanded(child: children[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One boxed line in a section.
class _Line extends StatelessWidget {
  const _Line({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(spacing: 12, children: children),
      ),
    );
  }
}
