import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/stats.dart';
import '../../services/catalogue_reader.dart';
import '../format.dart';
import '../instant.dart';
import '../text/strings.dart';
import '../theme.dart';
import '../sliding_row.dart';
import '../widgets.dart';
import 'stats_tree.dart';
import '../fit_text.dart';
import '../client_chip.dart';

/// How far back the statistics look.
enum StatsRange {
  weeks4(28, S.range4w),
  months3(91, S.range3m),
  months12(364, S.range12m);

  const StatsRange(this.days, this.word);

  final int days;
  final S word;
}

/// The statistics tab: a row of numbers against the previous range of the
/// same length, then one chart per card. Loads on first show and again
/// when the shell bumps [refresh].
class StatsView extends StatefulWidget {
  const StatsView({
    super.key,
    required this.now,
    required this.layout,
    this.reader,
    this.visible = true,
    this.refresh = 0,
    this.clientId,
    this.workId,
    this.filter,
    this.clients = const {},
  });

  /// The shared filter's client and work (null = all).
  final int? clientId;
  final int? workId;

  /// The shared filter button, shown first in the toolbar.
  final Widget? filter;

  /// Clients by id, for their chips.
  final Map<int, ClientTag> clients;

  final DateTime now;
  final ScreenLayout layout;
  final CatalogueReader? reader;

  /// False while another tab is in front: nothing loads until shown.
  final bool visible;

  /// Bumped by the shell after writes; reloads.
  final int refresh;

  @override
  State<StatsView> createState() => _StatsViewState();
}

/// The statistics as their summary (cards) or as the detail table — this
/// device's choice.
final statsAsTable = ValueNotifier<bool>(false);

class _StatsViewState extends State<StatsView> {
  /// The detail table's tree (its clients); null while it loads — a
  /// big document takes a moment.
  List<StatsNode>? _tree;
  int _treeAsked = 0;

  Future<void> _loadTree() async {
    final r = widget.reader;
    if (r == null) return;
    final ask = ++_treeAsked;
    final (from, to) = _span;
    if (_tree != null) setState(() => _tree = null);
    final root = await r.statsTree(
      from: from,
      to: to,
      clientId: widget.clientId,
      workId: widget.workId,
    );
    if (mounted && ask == _treeAsked) setState(() => _tree = root.children);
  }

  StatsBucket _bucket = StatsBucket.week;
  StatsRange _range = StatsRange.months3;
  Stats? _stats;
  int _loaded = -1;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    statsAsTable.addListener(_onTable);
    if (widget.visible) unawaited(_load());
    _onTable();
  }

  /// The period shown: the range back from the end of today.
  (DateTime, DateTime) get _span {
    final n = widget.now;
    final to = DateTime(n.year, n.month, n.day + 1);
    return (DateTime(to.year, to.month, to.day - _range.days), to);
  }

  @override
  void dispose() {
    statsAsTable.removeListener(_onTable);
    super.dispose();
  }

  /// The table chosen (here or remembered): its tree loads.
  void _onTable() {
    if (statsAsTable.value && widget.visible) unawaited(_loadTree());
  }

  @override
  void didUpdateWidget(StatsView old) {
    super.didUpdateWidget(old);
    final refilter =
        old.clientId != widget.clientId || old.workId != widget.workId;
    if (widget.visible &&
        (_loaded != widget.refresh || _stats == null || refilter)) {
      unawaited(_load());
      _onTable();
    }
  }

  Future<void> _load() async {
    final r = widget.reader;
    if (r == null) return;
    final ask = ++_asked;
    _loaded = widget.refresh;
    final (from, to) = _span;
    final s = await r.stats(
      from: from,
      to: to,
      bucket: _bucket,
      clientId: widget.clientId,
      workId: widget.workId,
    );
    if (mounted && ask == _asked) setState(() => _stats = s);
  }

  void _pick({StatsBucket? bucket, StatsRange? range}) {
    setState(() {
      _bucket = bucket ?? _bucket;
      _range = range ?? _range;
    });
    unawaited(_load());
    _onTable();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = _stats;
    return ColoredBox(
      color: c.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ViewToolbar(
            children: [
              ?widget.filter,
              SegmentGroup(
                children: [
                  for (final (b, w) in [
                    (StatsBucket.day, S.bDay),
                    (StatsBucket.week, S.bWeek),
                    (StatsBucket.month, S.bMonth),
                  ])
                    SegmentButton(
                      key: Key('stats-bucket-${b.name}'),
                      label: w.t,
                      selected: _bucket == b,
                      onTap: () => _pick(bucket: b),
                    ),
                ],
              ),
              ValueListenableBuilder<bool>(
                valueListenable: statsAsTable,
                builder: (context, table, _) => ToolbarButton(
                  key: const Key('stats-table'),
                  label: table ? S.statsSummary.t : S.statsTable.t,
                  icon: table
                      ? Icons.dashboard_outlined
                      : Icons.table_rows_outlined,
                  selected: table,
                  onTap: () => statsAsTable.value = !table,
                ),
              ),
              PopupMenuButton<StatsRange>(
                key: const Key('stats-range'),
                tooltip: '',
                popUpAnimationStyle: instant,
                onSelected: (r) => _pick(range: r),
                itemBuilder: (_) => [
                  for (final r in StatsRange.values)
                    CheckedPopupMenuItem(
                      key: Key('stats-range-${r.name}'),
                      value: r,
                      checked: r == _range,
                      child: Text(r.word.t),
                    ),
                ],
                child: ToolbarButton(
                  label: _range.word.t,
                  selected: false,
                  dropdown: true,
                ),
              ),
            ],
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: statsAsTable,
              builder: (context, table, summary) => table
                  ? switch (_tree) {
                      null => const Center(
                        key: Key('stats-tree-loading'),
                        child: CircularProgressIndicator(),
                      ),
                      final roots => StatsTreeTable(
                        roots: roots,
                        clientOf: (id) => widget.clients[id],
                      ),
                    }
                  : summary!,
              child: s == null
                  ? const SizedBox.shrink()
                  : OwnScroll(
                      builder: (controller) => Scrollbar(
                        controller: controller,
                        child: LayoutBuilder(
                          builder: (context, box) => SingleChildScrollView(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                            child: _body(context, s, box.maxWidth - 28),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Stats s, double width) {
    const gap = 12.0;
    final cols = width >= 1000 ? 3 : (width >= 640 ? 2 : 1);
    final cardWidth = (width - gap * (cols - 1)) / cols;
    final kpiCols = width >= 1180 ? 8 : (width >= 560 ? 4 : 2);
    final kpiWidth = (width - 8 * (kpiCols - 1)) / kpiCols;
    final cards = <Widget>[
      _paceCard(context, s),
      _worksCard(context, s),
      _clientsCard(context, s),
      _latenessCard(context, s),
      _takesCard(context, s),
      _heatCard(context, s),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: [
        // Short screens (a phone held sideways) keep the numbers to one
        // row that scrolls sideways, so the charts start on screen.
        if (MediaQuery.sizeOf(context).height < 500)
          SlidingRow(
            key: const Key('stats-kpi-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              for (final k in _kpis(context, s)) SizedBox(width: 150, child: k),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in _kpis(context, s))
                SizedBox(width: kpiWidth, child: k),
            ],
          ),
        _doneCard(context, s),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        ),
        _lanesCard(context, s),
      ],
    );
  }

  // Numbers.

  List<Widget> _kpis(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final p = s.previous;
    final t = s.total;
    final workDays = s.days.where((d) => d.worked > 0).length;
    final handedIn = s.onTime + s.late;
    final firstIn = s.onTimeFirst + s.lateFirst;
    final extended = s.extensions.entries
        .where((e) => e.key > 0)
        .fold(0, (n, e) => n + e.value);
    List<String> money(Map<String, num> m) => [
      for (final e in m.entries) formatMoney(e.key, e.value.round()),
    ];
    final earned = money(t.earned);
    final hourly = money(s.hourly);
    return [
      _Kpi(
        label: S.kDone.t,
        value: '${t.done} cut',
        note: _delta(context, t.done, p?.total.done),
      ),
      _Kpi(
        label: S.kWorked.t,
        value: S.hours.f({'n': _hours(t.worked)}),
        note: Text(
          workDays == 0
              ? '—'
              : S.perDayAvg.f({
                  'v': S.hours.f({
                    'n': _hours(
                      Duration(seconds: t.worked.inSeconds ~/ workDays),
                    ),
                  }),
                }),
          style: TextStyle(color: c.muted),
        ),
      ),
      _Kpi(
        label: S.kPerCut.t,
        value: t.perCut == null ? '—' : S.minutes.f({'n': t.perCut!.inMinutes}),
        note: _delta(
          context,
          t.perCut?.inMinutes,
          p?.total.perCut?.inMinutes,
          lowerIsBetter: true,
        ),
      ),
      _Kpi(
        label: S.kHourly.t,
        value: hourly.isEmpty ? '—' : '${hourly.first}/h',
        note: Text(
          hourly.skip(1).map((h) => '$h/h').join(' · '),
          style: TextStyle(color: c.muted),
        ),
      ),
      _Kpi(
        label: S.kOnTime.t,
        value: handedIn == 0 ? '—' : '${(s.onTime * 100 / handedIn).round()}%',
        note: Text(
          S.lateN.f({'n': s.late}),
          style: TextStyle(color: s.late > 0 ? c.retake : c.muted),
        ),
      ),
      // Against the first deadline given, before any extension.
      _Kpi(
        label: S.kFirstDue.t,
        value: firstIn == 0
            ? '—'
            : '${(s.onTimeFirst * 100 / firstIn).round()}%',
        note: Text(
          S.extendedN.f({'n': extended}),
          style: TextStyle(color: c.muted),
        ),
      ),
      _Kpi(
        label: S.kRetake.t,
        value: t.retakeRate == null ? '—' : '${(t.retakeRate! * 100).round()}%',
        note: _delta(
          context,
          t.retakeRate == null ? null : (t.retakeRate! * 100).round(),
          p?.total.retakeRate == null
              ? null
              : (p!.total.retakeRate! * 100).round(),
          lowerIsBetter: true,
          points: true,
        ),
      ),
      _Kpi(
        label: S.kEarned.t,
        value: earned.isEmpty ? '—' : earned.first,
        note: Text(
          earned.skip(1).join(' · '),
          style: TextStyle(color: c.muted),
        ),
      ),
    ];
  }

  /// 「▲ 12%」 against the previous range; green when better.
  Widget _delta(
    BuildContext context,
    int? now,
    int? before, {
    bool lowerIsBetter = false,
    bool points = false,
  }) {
    final c = AppColors.of(context);
    if (now == null || before == null || (!points && before == 0)) {
      return Text(S.vsPrev.t, style: TextStyle(color: c.faint));
    }
    final diff = points
        ? now - before
        : ((now - before) * 100 / before).round();
    if (diff == 0) {
      return Text('± 0 · ${S.vsPrev.t}', style: TextStyle(color: c.muted));
    }
    final better = (diff < 0) == lowerIsBetter;
    return FitText(
      '${diff > 0 ? '▲' : '▼'} ${diff.abs()}${points ? 'pt' : '%'} · ${S.vsPrev.t}',
      style: TextStyle(color: better ? c.done : c.retake),
    );
  }

  static String _hours(Duration d) {
    final h = d.inMinutes / 60;
    return h >= 10 ? '${h.round()}' : h.toStringAsFixed(1);
  }

  // Cards.

  Widget _doneCard(BuildContext context, Stats s) {
    final values = [for (final p in s.periods) p.done.toDouble()];
    final labels = [for (final p in s.periods) _periodLabel(p.start)];
    final avg = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;
    return _Card(
      title: S.cDoneCuts.t,
      note: S.cAvgLine.t,
      child: SizedBox(
        height: 160,
        child: CustomPaint(
          painter: _BarsPainter(
            values: values,
            labels: labels,
            colors: [Theme.of(context).colorScheme.primary],
            colors2: AppColors.of(context),
            average: avg,
            averageLabel: S.average.f({'v': avg.toStringAsFixed(1)}),
            text: DefaultTextStyle.of(context).style,
          ),
        ),
      ),
    );
  }

  String _periodLabel(DateTime d) => switch (_bucket) {
    StatsBucket.day => '${d.day}',
    StatsBucket.week => '${d.month}/${d.day}',
    StatsBucket.month => monthName(d.month),
  };

  Widget _paceCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final paces = s.stagePaces;
    final top = paces.fold<double>(
      0,
      (m, p) =>
          math.max(m, math.max(p.overall.perDay ?? 0, p.recent.perDay ?? 0)),
    );
    String one(double? v) => v == null ? '—' : v.toStringAsFixed(1);
    return _Card(
      title: S.cPace.t,
      note: S.cPaceNote.t,
      child: _rowsOrEmpty(context, [
        for (final p in paces)
          _BarRow(
            label: stageText(p.stageName),
            value: '${one(p.overall.perDay)} · ${one(p.recent.perDay)}',
            bar: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
                _Track(
                  parts: [((p.overall.perDay ?? 0) / _nz(top), c.faint)],
                  height: 5,
                ),
                _Track(
                  parts: [((p.recent.perDay ?? 0) / _nz(top), accent)],
                  height: 5,
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _worksCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final top = s.works.fold<int>(0, (m, w) => math.max(m, w.cuts));
    return _Card(
      title: S.cWorks.t,
      note: S.cWorksNote.t,
      child: _rowsOrEmpty(context, [
        for (final w in s.works)
          _BarRow(
            label: w.label ?? '—',
            value: '${w.finished}/${w.cuts} cut',
            valueWidth: 120,
            bar: _Track(
              parts: [
                (w.finished / _nz(top), c.done),
                ((w.cuts - w.finished) / _nz(top), c.line),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _clientsCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final top = s.clients.fold<int>(0, (m, x) => math.max(m, x.handed));
    return _Card(
      title: S.cClients.t,
      note: S.cClientsNote.t,
      child: _rowsOrEmpty(context, [
        for (final x in s.clients)
          _BarRow(
            label: x.label ?? '—',
            lead: switch (widget.clients[x.key]) {
              final t? => ClientChip(t),
              null => null,
            },
            value: [
              '${x.handed} cut',
              for (final e in x.earned.entries) formatMoney(e.key, e.value),
            ].join(' · '),
            valueWidth: 150,
            bar: _Track(parts: [(x.handed / _nz(top), c.submitted)]),
          ),
      ]),
    );
  }

  Widget _latenessCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    int sum(bool Function(int days) f) => s.lateness.entries
        .where((e) => f(e.key))
        .fold(0, (n, e) => n + e.value);
    final rows = [
      (S.early.t, sum((d) => d < 0), c.done),
      (S.onDay.t, sum((d) => d == 0), c.done),
      (S.late1.t, sum((d) => d == 1), c.retake),
      (S.late2to3.t, sum((d) => d >= 2 && d <= 3), c.retake),
      (S.late4.t, sum((d) => d >= 4), c.retake),
      if (s.noDue > 0) (S.noDue.t, s.noDue, c.faint),
    ];
    final top = rows.fold<int>(0, (m, r) => math.max(m, r.$2));
    return _Card(
      title: S.cLateness.t,
      note: S.cLatenessNote.t,
      child: top == 0
          ? _empty(context)
          : Column(
              spacing: 6,
              children: [
                for (final (l, n, color) in rows)
                  _BarRow(
                    label: l,
                    value: '$n',
                    bar: _Track(parts: [(n / top, color)]),
                  ),
              ],
            ),
    );
  }

  Widget _takesCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final most = s.takes.keys.fold(1, math.max);
    final shown = math.max(3, math.min(most, 4));
    final values = [
      for (var t = 1; t <= shown; t++)
        (t < shown
                ? s.takes[t] ?? 0
                : s.takes.entries
                      .where((e) => e.key >= shown)
                      .fold(0, (n, e) => n + e.value))
            .toDouble(),
    ];
    final rate = s.total.retakeRate;
    return _Card(
      title: S.cTakes.t,
      note: rate == null ? null : '${S.kRetake.t} ${(rate * 100).round()}%',
      child: values.every((v) => v == 0)
          ? _empty(context)
          : SizedBox(
              height: 130,
              child: CustomPaint(
                painter: _BarsPainter(
                  values: values,
                  labels: [
                    for (var t = 1; t <= shown; t++)
                      if (t == shown && most > shown) 'T$t+' else 'T$t',
                  ],
                  colors: [c.done, for (var t = 2; t <= shown; t++) c.retake],
                  colors2: c,
                  text: DefaultTextStyle.of(context).style,
                  showValues: true,
                ),
              ),
            ),
    );
  }

  Widget _heatCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final any = s.heatmap.any((d) => d.any((h) => h > Duration.zero));
    return _Card(
      title: S.cHeat.t,
      note: S.cHeatNote.t,
      child: !any
          ? _empty(context)
          : SizedBox(
              height: 7 * 15 + 16,
              child: CustomPaint(
                painter: _HeatPainter(
                  heat: s.heatmap,
                  color: Theme.of(context).colorScheme.primary,
                  empty: c.line,
                  weekdays: weekdayNames(),
                  text: DefaultTextStyle.of(context).style
                      .copyWith(color: c.muted),
                ),
              ),
            ),
    );
  }

  Widget _lanesCard(BuildContext context, Stats s) {
    final c = AppColors.of(context);
    final days = s.days.length > 56
        ? s.days.sublist(s.days.length - 56)
        : s.days;
    return _Card(
      title: S.cLanes.t,
      note: S.cLanesNote.t,
      child: SizedBox(
        height: 120,
        child: CustomPaint(
          painter: _LanesPainter(
            worked: [for (final d in days) d.worked],
            planned: [for (final d in days) d.planned],
            lanes: s.lanes,
            color: Theme.of(context).colorScheme.primary,
            capColor: c.retake,
            capLabel: S.lanesN.f({'n': s.lanes}),
            startLabel: days.isEmpty ? '' : formatDate(days.first.day),
            endLabel: S.today.t,
            text: DefaultTextStyle.of(context).style.copyWith(color: c.muted),
          ),
        ),
      ),
    );
  }

  Widget _rowsOrEmpty(BuildContext context, List<Widget> rows) =>
      rows.isEmpty ? _empty(context) : Column(spacing: 6, children: rows);

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      S.noData.t,
      style: TextStyle(color: AppColors.of(context).faint),
    ),
  );

  static double _nz(num v) => v == 0 ? 1 : v.toDouble();
}

/// One number tile: what it is, the number, and one line under it.
class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final Widget note;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          FitText(label, style: TextStyle(fontSize: 11, color: c.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: SizedBox(width: double.infinity, child: note),
          ),
        ],
      ),
    );
  }
}

/// A chart card: title, a quiet note, then its content.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.note});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text.rich(
            TextSpan(
              text: title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              children: [
                if (note != null)
                  TextSpan(
                    text: '  $note',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: c.muted,
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Label · bar · value, the rows inside a card.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.bar,
    required this.value,
    this.valueWidth = 86,
    this.lead,
  });

  final String label;

  /// Shown instead of [label] (a client's chip).
  final Widget? lead;
  final Widget bar;
  final String value;
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      spacing: 8,
      children: [
        SizedBox(
          width: 88,
          child: lead ?? FitText(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(child: bar),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: valueWidth),
          child: FitText(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: c.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// A rounded track filled by [parts] (share 0–1, colour) from the left.
class _Track extends StatelessWidget {
  const _Track({required this.parts, this.height = 8});

  final List<(double, Color)> parts;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      painter: _TrackPainter(parts, AppColors.of(context).panel),
    ),
  );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.parts, this.background);

  final List<(double, Color)> parts;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(whole, Paint()..color = background);
    canvas.save();
    canvas.clipRRect(whole);
    var x = 0.0;
    for (final (share, color) in parts) {
      final w = size.width * share.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w, size.height),
        Paint()..color = color,
      );
      x += w;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.parts.toString() != parts.toString() || old.background != background;
}

TextPainter _label(String s, TextStyle style, {double size = 10}) =>
    TextPainter(
      text: TextSpan(
        text: s,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

/// Vertical bars with a light grid, optional average line and labels
/// thinned so they never run together.
class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.labels,
    required this.colors,
    required this.colors2,
    required this.text,
    this.average,
    this.averageLabel,
    this.showValues = false,
  });

  final List<double> values;
  final List<String> labels;

  /// One colour per bar, or one for all.
  final List<Color> colors;
  final AppColors colors2;
  final TextStyle text;
  final double? average;
  final String? averageLabel;
  final bool showValues;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final muted = text.copyWith(color: colors2.muted);
    final top = values.fold(0.0, math.max) * 1.15;
    final max = top == 0 ? 1.0 : top;
    const bottom = 16.0;
    const left = 24.0;
    final h = size.height - bottom - (showValues ? 14 : 6);
    final base = size.height - bottom;
    final grid = Paint()
      ..color = colors2.line
      ..strokeWidth = 1;
    if (!showValues) {
      for (final f in [0.0, 0.5, 1.0]) {
        final y = base - f * h;
        canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
        _label('${(f * max).round()}', muted).paint(canvas, Offset(0, y - 6));
      }
    }
    final x0 = showValues ? 0.0 : left;
    final bw = (size.width - x0) / values.length;
    final labelW = labels.fold(
      0.0,
      (m, l) => math.max(m, _label(l, muted).width),
    );
    final every = math.max(1, ((labelW + 6) / bw).ceil());
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final bh = v / max * h;
      final color = colors[i % colors.length];
      final last = i == values.length - 1 && colors.length == 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x0 + i * bw + bw * 0.18, base - bh, bw * 0.64, bh),
          const Radius.circular(2),
        ),
        Paint()
          ..color = colors.length == 1 && !last
              ? color.withValues(alpha: 0.55)
              : color,
      );
      if (showValues) {
        final t = _label('${v.round()}', text, size: 11);
        t.paint(
          canvas,
          Offset(x0 + i * bw + (bw - t.width) / 2, base - bh - 14),
        );
      }
      if ((values.length - 1 - i) % every == 0) {
        final t = _label(labels[i], muted);
        t.paint(
          canvas,
          Offset(x0 + i * bw + (bw - t.width) / 2, size.height - 12),
        );
      }
    }
    final avg = average;
    if (avg != null && avg > 0) {
      final y = base - avg / max * h;
      final p = Paint()
        ..color = colors2.submitted
        ..strokeWidth = 1.2;
      for (var x = left; x < size.width; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          p,
        );
      }
      if (averageLabel != null) {
        final t = _label(
          averageLabel!,
          text.copyWith(color: colors2.submitted),
        );
        t.paint(canvas, Offset(size.width - t.width, y - 13));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

/// Weekday × hour squares, darker for more timer time.
class _HeatPainter extends CustomPainter {
  _HeatPainter({
    required this.heat,
    required this.color,
    required this.empty,
    required this.weekdays,
    required this.text,
  });

  final List<List<Duration>> heat;
  final Color color;
  final Color empty;
  final List<String> weekdays;
  final TextStyle text;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const gap = 2.0;
    final cw = (size.width - left) / 24;
    const ch = 13.0;
    final top = heat
        .expand((d) => d)
        .fold(Duration.zero, (m, d) => d > m ? d : m)
        .inSeconds;
    for (var d = 0; d < 7; d++) {
      final y = d * (ch + gap);
      _label(weekdays[d], text).paint(canvas, Offset(0, y + 1));
      for (var h = 0; h < 24; h++) {
        final v = top == 0 ? 0.0 : heat[d][h].inSeconds / top;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left + h * cw, y, cw - gap, ch),
            const Radius.circular(2),
          ),
          Paint()
            ..color = v == 0
                ? empty.withValues(alpha: 0.5)
                : color.withValues(alpha: 0.15 + 0.85 * v),
        );
      }
    }
    for (var h = 0; h < 24; h += 6) {
      _label(
        '$h',
        text,
      ).paint(canvas, Offset(left + h * cw, 7 * (ch + gap) + 2));
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => true;
}

/// Groups worked per day as a line over the planned ones (faint area),
/// with the lane count as a dashed cap.
class _LanesPainter extends CustomPainter {
  _LanesPainter({
    required this.worked,
    required this.planned,
    required this.lanes,
    required this.color,
    required this.capColor,
    required this.capLabel,
    required this.startLabel,
    required this.endLabel,
    required this.text,
  });

  final List<int> worked;
  final List<int> planned;
  final int lanes;
  final Color color;
  final Color capColor;
  final String capLabel;
  final String startLabel;
  final String endLabel;
  final TextStyle text;

  @override
  void paint(Canvas canvas, Size size) {
    if (worked.isEmpty) return;
    final top = math
        .max(lanes + 1, [...worked, ...planned].fold(0, math.max))
        .toDouble();
    const bottom = 16.0;
    final h = size.height - bottom - 8;
    final base = size.height - bottom;
    double x(int i) =>
        worked.length == 1 ? 0 : i / (worked.length - 1) * size.width;
    double y(int v) => base - v / top * h;

    final area = Path()..moveTo(0, base);
    for (var i = 0; i < planned.length; i++) {
      area.lineTo(x(i), y(planned[i]));
    }
    area
      ..lineTo(size.width, base)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));

    final line = Path()..moveTo(x(0), y(worked[0]));
    for (var i = 1; i < worked.length; i++) {
      line.lineTo(x(i), y(worked[i]));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    final cap = y(lanes);
    final p = Paint()
      ..color = capColor
      ..strokeWidth = 1.2;
    for (var dx = 0.0; dx < size.width; dx += 7) {
      canvas.drawLine(
        Offset(dx, cap),
        Offset(math.min(dx + 4, size.width), cap),
        p,
      );
    }
    final c = _label(capLabel, text.copyWith(color: capColor));
    c.paint(canvas, Offset(size.width - c.width, cap - 13));
    _label(startLabel, text).paint(canvas, Offset(0, size.height - 12));
    final e = _label(endLabel, text);
    e.paint(canvas, Offset(size.width - e.width, size.height - 12));
  }

  @override
  bool shouldRepaint(_LanesPainter old) => true;
}
