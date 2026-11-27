import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/clock.dart';
import '../../core/size_class.dart';
import '../../models/progress.dart';
import '../../services/catalogue_reader.dart';
import '../../services/work_timer.dart';
import '../format.dart';
import '../part_line.dart';
import '../theme.dart';
import '../timer_card.dart';
import '../widgets.dart';

/// Today: the timer, how many cuts today asks for, the work whose plan has
/// started, then work not started yet (dimmed). Usual pace and this
/// month's total stay folded until asked for.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.reader,
    required this.layout,
    this.timer,
    this.clock = systemClock,
  });

  final CatalogueReader reader;
  final ScreenLayout layout;

  /// Writes timer intervals; null leaves the timer read-only.
  final WorkTimerStore? timer;
  final Clock clock;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  TodayView _today = TodayView.empty;
  List<UsualPace>? _paces;
  MonthlyTotals? _month;
  final _expanded = <String>{};
  String? _selected;
  bool _openPace = false;
  bool _openMonth = false;
  int? _lastTask;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _lastTask = widget.timer?.running()?.taskId;
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final today = await widget.reader.today();
    if (mounted) setState(() => _today = today);
  }

  Future<void> _loadPaces() async {
    final p = [for (final s in await widget.reader.stagePaces()) s.recent];
    if (mounted) setState(() => _paces = p);
  }

  Future<void> _loadMonth() async {
    final now = widget.clock().toLocal();
    final m = await widget.reader.monthlyTotals(now.year, now.month);
    if (mounted) setState(() => _month = m);
  }

  void _startOn(TaskRow t) {
    final timer = widget.timer;
    if (timer == null) return;
    timer
      ..stop()
      ..start(taskId: t.id);
    setState(() => _lastTask = t.id);
    unawaited(_load());
  }

  void _stop() {
    widget.timer?.stop();
    setState(() {});
    unawaited(_load());
  }

  void _resume() {
    final id = _lastTask;
    if (id == null) return;
    widget.timer?.start(taskId: id);
    setState(() {});
  }

  ({TaskRow? task, PartGroup? group}) _find(int? taskId) {
    if (taskId == null) return (task: null, group: null);
    for (final e in _today.entries) {
      for (final t in e.group.tasks) {
        if (t.id == taskId) return (task: t, group: e.group);
      }
    }
    return (task: null, group: null);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final running = widget.timer?.running();
    final shown = _find(running?.taskId ?? _lastTask);
    final wide = widget.layout.size == SizeClass.wide;
    final timerCard = TimerCard(
      running: running,
      task: shown.task,
      group: shown.group,
      onStop: _stop,
      onResume: _resume,
      clock: widget.clock,
      large: widget.layout.size != SizeClass.narrow,
    );
    final folds = _Folds(
      children: [
        _Fold(
          key: const Key('fold-pace'),
          label: '평소 속도',
          open: _openPace,
          onTap: () {
            setState(() => _openPace = !_openPace);
            if (_openPace && _paces == null) unawaited(_loadPaces());
          },
          child: _PaceTable(paces: _paces),
        ),
        _Fold(
          key: const Key('fold-month'),
          label: '이번 달 완료',
          value: _month?.entries
              .map((e) => formatMoney(e.key, e.value.total))
              .join(' · '),
          open: _openMonth,
          onTap: () {
            setState(() => _openMonth = !_openMonth);
            if (_month == null) unawaited(_loadMonth());
          },
        ),
      ],
    );
    final list = _TodayList(
      today: _today,
      expanded: _expanded,
      selected: _selected,
      runningTask: running?.taskId,
      controller: _scroll,
      onToggle: (g) => setState(() {
        _selected = g.key;
        if (!_expanded.remove(g.key)) _expanded.add(g.key);
      }),
      onTask: widget.timer == null ? null : _startOn,
    );
    return ColoredBox(
      color: c.panelAlt,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Expanded(child: list),
                  SizedBox(
                    width: 380,
                    child: Column(spacing: 12, children: [timerCard, folds]),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  timerCard,
                  Expanded(child: list),
                  folds,
                ],
              ),
      ),
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({
    required this.today,
    required this.expanded,
    required this.selected,
    required this.runningTask,
    required this.controller,
    required this.onToggle,
    required this.onTask,
  });

  final TodayView today;
  final Set<String> expanded;
  final String? selected;
  final int? runningTask;
  final ScrollController controller;
  final ValueChanged<PartGroup> onToggle;
  final ValueChanged<TaskRow>? onTask;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final started = [
      for (final e in today.entries)
        if (!e.beforePlan) e,
    ];
    final later = [
      for (final e in today.entries)
        if (e.beforePlan) e,
    ];
    final rows = <Widget>[
      for (final e in started) ..._entry(e),
      if (later.isNotEmpty) _Section('시작 전', later.length),
      for (final e in later) ..._entry(e),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    spacing: 8,
                    children: [
                      const Text(
                        '오늘',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${today.cutsToday.toStringAsFixed(1)}컷',
                        key: const Key('cuts-today'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(controller: controller, children: rows),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _entry(TodayEntry e) {
    final g = e.group;
    final open = expanded.contains(g.key);
    return [
      PartLine(
        group: g,
        now: DateTime(0),
        dayStartMinutes: 0,
        expanded: open,
        selected: selected == g.key,
        dimmed: e.beforePlan,
        signal: DueText.days(e.dueInDays, g.status),
        onTap: () => onToggle(g),
      ),
      if (open)
        PartDetails(
          group: g,
          pace: e.pace,
          extra: [
            if (e.beforePlan && g.planStartAt != null)
              ('시작', formatDate(g.planStartAt)),
          ],
          highlighted: runningTask,
          onTask: onTask,
        ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
          const Spacer(),
          Text('$count', style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ),
    );
  }
}

class _Folds extends StatelessWidget {
  const _Folds({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// One folded line: a label, an optional value, and what opens below.
class _Fold extends StatelessWidget {
  const _Fold({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
    this.value,
    this.child,
  });

  final String label;
  final String? value;
  final bool open;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 10,
                children: [
                  Text(label),
                  const Spacer(),
                  if (value != null)
                    Text(
                      value!,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open && child != null) child!,
        Divider(height: 1, color: c.line),
      ],
    );
  }
}

class _PaceTable extends StatelessWidget {
  const _PaceTable({required this.paces});

  final List<UsualPace>? paces;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final list = paces ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        spacing: 4,
        children: [
          for (final p in list)
            Row(
              children: [
                Text(p.stageName),
                const Spacer(),
                Text(
                  p.perDay == null ? '—' : '${p.perDay!.toStringAsFixed(1)}컷/일',
                  style: TextStyle(
                    color: c.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
