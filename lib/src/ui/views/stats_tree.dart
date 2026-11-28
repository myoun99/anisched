import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../client_chip.dart';
import '../fit_text.dart';
import '../format.dart';
import '../palette.dart';
import '../text/strings.dart';
import '../theme.dart';
import '../widgets.dart';

/// The statistics' detail table rows, client → work → episode → unit (a
/// part × stage, or an episode's loose cuts × stage) → cut. The view's
/// own shape; the store's tree maps onto it.
enum StatsLevel { client, work, episode, unit, cut }

class StatsNode {
  const StatsNode({
    required this.key,
    required this.level,
    required this.label,
    this.clientColor,
    this.stageName,
    this.cuts = 0,
    this.worked = Duration.zero,
    this.pay = 0,
    this.currency = 'JPY',
    this.dueKept = 0,
    this.dueTotal = 0,
    this.retakes = 0,
    this.children = const [],
    this.workedByStage,
    this.intervals,
    this.retakeRound,
    this.status,
  });

  final String key;
  final StatsLevel level;
  final String label;
  final Color? clientColor;
  final String? stageName;

  /// Cuts, a shared group counting once.
  final int cuts;
  final Duration worked;
  final int pay;
  final String currency;

  /// Deadlines kept of those due (handed in on time).
  final int dueKept;
  final int dueTotal;
  final int retakes;
  final List<StatsNode> children;

  /// A cut's own: time per stage, timer runs, its take, its state.
  final Map<String, Duration>? workedByStage;
  final int? intervals;
  final int? retakeRound;
  final TaskStatus? status;

  Duration? get perCut =>
      cuts == 0 ? null : Duration(seconds: worked.inSeconds ~/ cuts);

  /// Pay per hour worked; null with no time.
  double? get hourly =>
      worked.inMinutes == 0 ? null : pay / (worked.inMinutes / 60);
}

/// The table's columns, most telling first: a narrow screen shows the
/// first ones on the row, the rest when the row opens.
enum StatsColumn {
  cuts,
  worked,
  perCut,
  pay,
  hourly,
  dueKept,
  retakes;

  String get title => switch (this) {
    cuts => 'cut',
    worked => S.kWorked.t,
    perCut => S.kPerCut.t,
    pay => S.colPay.t,
    hourly => S.kHourly.t,
    dueKept => S.kOnTime.t,
    retakes => S.colRetakes.t,
  };

  /// The value a sort goes by.
  num sortValue(StatsNode n) => switch (this) {
    cuts => n.cuts,
    worked => n.worked.inSeconds,
    perCut => n.perCut?.inSeconds ?? -1,
    pay => n.pay,
    hourly => n.hourly ?? -1,
    dueKept => n.dueTotal == 0 ? -1 : n.dueKept / n.dueTotal,
    retakes => n.retakes,
  };

  String text(StatsNode n) => switch (this) {
    cuts => '${n.cuts}',
    worked => formatWorked(n.worked),
    perCut => n.perCut == null ? '—' : formatWorked(n.perCut!),
    pay => formatMoney(n.currency, n.pay),
    hourly =>
      n.hourly == null ? '—' : formatMoney(n.currency, n.hourly!.round()),
    dueKept => n.dueTotal == 0 ? '—' : '${n.dueKept}/${n.dueTotal}',
    retakes => '${n.retakes}',
  };
}

/// The statistics as a table that opens down the tree: only the rows in
/// sight are built. A column's head sorts by it, within each level (a
/// second tap turns the order). A row opens into its children; on a
/// narrow screen it also shows, under it, the columns that did not fit;
/// a cut shows its time per stage, timer runs, take and state.
class StatsTreeTable extends StatefulWidget {
  const StatsTreeTable({super.key, required this.roots});

  final List<StatsNode> roots;

  @override
  State<StatsTreeTable> createState() => _StatsTreeTableState();
}

class _StatsTreeTableState extends State<StatsTreeTable> {
  final _open = <String>{};
  StatsColumn? _sort;
  bool _descending = true;

  static const _rowHeight = 40.0;
  static const _colWidth = 84.0;
  static const _nameMin = 170.0;

  List<StatsNode> _sorted(List<StatsNode> nodes) {
    final by = _sort;
    if (by == null) return nodes;
    final list = [...nodes]
      ..sort((a, b) => by.sortValue(a).compareTo(by.sortValue(b)));
    return _descending ? list.reversed.toList() : list;
  }

  /// The rows in sight order: each node, its opened line (when it has
  /// something to say), then its children when open.
  List<(StatsNode, int, bool)> _rows(int shown) {
    final out = <(StatsNode, int, bool)>[];
    void walk(List<StatsNode> nodes, int depth) {
      for (final n in _sorted(nodes)) {
        out.add((n, depth, false));
        if (!_open.contains(n.key)) continue;
        final hidden = shown < StatsColumn.values.length;
        if (hidden || n.level == StatsLevel.cut) out.add((n, depth, true));
        walk(n.children, depth + 1);
      }
    }

    walk(widget.roots, 0);
    return out;
  }

  void _sortBy(StatsColumn c) => setState(() {
    if (_sort == c) {
      _descending = !_descending;
    } else {
      _sort = c;
      _descending = true;
    }
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = box.maxWidth - _nameMin;
      final shown = (room / _colWidth).floor().clamp(
        2,
        StatsColumn.values.length,
      );
      final rows = _rows(shown);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(context, shown),
          Expanded(
            child: ListView.builder(
              key: const Key('stats-tree'),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final (n, depth, line) = rows[i];
                return line
                    ? _openLine(context, n, depth, shown)
                    : _row(context, n, depth, shown);
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _head(BuildContext context, int shown) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            const Expanded(child: SizedBox()),
            for (final col in StatsColumn.values.take(shown))
              InkWell(
                key: Key('stats-sort-${col.name}'),
                onTap: () => _sortBy(col),
                child: SizedBox(
                  width: _colWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_sort == col)
                        Icon(
                          _descending
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          size: 12,
                          color: c.muted,
                        ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: FitText(
                            col.title,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 11, color: c.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _name(BuildContext context, StatsNode n) => switch (n.level) {
    StatsLevel.client => ClientChip((
      name: n.label,
      color: n.clientColor ?? clientSwatches.first,
    )),
    StatsLevel.unit => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Dot(stageColor(n.stageName ?? '')),
        Flexible(child: FitText(n.label)),
      ],
    ),
    StatsLevel.work || StatsLevel.episode => FitText(
      n.label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    StatsLevel.cut => FitText(n.label),
  };

  Widget _row(BuildContext context, StatsNode n, int depth, int shown) {
    final c = AppColors.of(context);
    final open = _open.contains(n.key);
    final opens =
        n.children.isNotEmpty ||
        n.level == StatsLevel.cut ||
        shown < StatsColumn.values.length;
    return InkWell(
      key: Key('stats-row-${n.key}'),
      onTap: opens
          ? () => setState(() => open ? _open.remove(n.key) : _open.add(n.key))
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: SizedBox(
          height: _rowHeight,
          child: Row(
            children: [
              SizedBox(width: 8.0 + depth * 14),
              SizedBox(
                width: 18,
                child: opens
                    ? Icon(
                        open ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: c.muted,
                      )
                    : null,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _name(context, n),
                ),
              ),
              for (final col in StatsColumn.values.take(shown))
                SizedBox(
                  width: _colWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: FitText(
                      col.text(n),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Under an opened row: the columns that did not fit, and for a cut its
  /// time per stage (bars in the stage colours), timer runs, take and
  /// state.
  Widget _openLine(BuildContext context, StatsNode n, int depth, int shown) {
    final c = AppColors.of(context);
    final hidden = StatsColumn.values.skip(shown);
    final byStage = n.workedByStage ?? const {};
    final most = byStage.values.fold(Duration.zero, (a, b) => a > b ? a : b);
    return Container(
      key: Key('stats-open-${n.key}'),
      color: c.panelAlt,
      padding: EdgeInsets.fromLTRB(34.0 + depth * 14, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          if (hidden.isNotEmpty)
            Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                for (final col in hidden)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${col.title}  ',
                          style: TextStyle(fontSize: 11, color: c.muted),
                        ),
                        TextSpan(text: col.text(n)),
                      ],
                    ),
                  ),
              ],
            ),
          if (n.level == StatsLevel.cut) ...[
            for (final MapEntry(key: stage, value: d) in byStage.entries)
              Row(
                spacing: 8,
                children: [
                  SizedBox(
                    width: 52,
                    child: FitText(
                      stageText(stage),
                      style: TextStyle(fontSize: 11, color: c.muted),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          key: Key('stats-stage-$stage'),
                          height: 8,
                          width: most == Duration.zero
                              ? 0
                              : box.maxWidth * d.inSeconds / most.inSeconds,
                          decoration: BoxDecoration(
                            color: stageColor(stage),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      formatWorked(d),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            Wrap(
              spacing: 14,
              children: [
                if (n.intervals case final k?)
                  Text(
                    S.timerRuns.f({'n': k}),
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                if (n.retakeRound case final r? when r > 1)
                  Text(
                    S.retakeRound.f({'n': r}),
                    style: TextStyle(fontSize: 11, color: c.retake),
                  ),
                if (n.status case final st?)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Dot(c.of(st)),
                      Text(st.label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
