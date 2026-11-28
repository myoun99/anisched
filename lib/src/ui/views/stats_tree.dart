import 'package:flutter/material.dart';

import '../../models/stats.dart';
import '../client_chip.dart';
import '../fit_text.dart';
import '../format.dart';
import '../palette.dart';
import '../text/strings.dart';
import '../theme.dart';
import '../widgets.dart';

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

  /// The value a sort goes by (several currencies: their sum, a rough
  /// order only).
  num sortValue(StatsNode n) => switch (this) {
    cuts => n.cuts,
    worked => n.worked.inSeconds,
    perCut => n.perCut?.inSeconds ?? -1,
    pay => n.earned.values.fold(0, (a, b) => a + b),
    hourly => n.perHour.values.fold(0.0, (a, b) => a + b),
    dueKept => n.onTimeRate ?? -1,
    retakes => n.retaken,
  };

  String text(StatsNode n) => switch (this) {
    cuts => '${n.cuts}',
    worked => formatWorked(n.worked),
    perCut => n.perCut == null ? '—' : formatWorked(n.perCut!),
    pay => moneyText(n.earned),
    hourly => moneyText({
      for (final e in n.perHour.entries) e.key: e.value.round(),
    }),
    dueKept => n.withDue == 0 ? '—' : '${n.onTime}/${n.withDue}',
    retakes => '${n.retaken}',
  };
}

/// Amounts in several currencies side by side: 「¥12,000 · ₩30,000」.
String moneyText(Money m) => m.isEmpty
    ? '—'
    : [for (final e in m.entries) formatMoney(e.key, e.value)].join(' · ');

/// The statistics as a table that opens down the tree: only the rows in
/// sight are built. A column's head sorts by it, within each level (a
/// second tap turns the order). A row opens into its children; on a
/// narrow screen it also shows, under it, the columns that did not fit;
/// a cut shows its stage time, timer runs, take and state.
class StatsTreeTable extends StatefulWidget {
  const StatsTreeTable({super.key, required this.roots, this.clientOf});

  /// The top rows (the tree's clients).
  final List<StatsNode> roots;

  /// A client's chip by id; null: its name alone (「회사 없음」 without one).
  final ClientTag? Function(int id)? clientOf;

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

  Widget _name(BuildContext context, StatsNode n) {
    final label = n.label;
    return switch (n.level) {
      StatsLevel.client => switch (n.clientId) {
        final int id when widget.clientOf?.call(id) != null => ClientChip(
          widget.clientOf!(id)!,
        ),
        _ => FitText(label ?? S.noClient.t),
      },
      StatsLevel.work || StatsLevel.episode => FitText(
        label ?? '—',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      // A unit: its part (or storyboard) at one stage; a cut at its
      // unit's stage.
      StatsLevel.unit || StatsLevel.cut || StatsLevel.all => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (n.stageName case final stage?) Dot(stageColor(stage)),
          Flexible(child: FitText(_title(n))),
        ],
      ),
    };
  }

  /// A unit's part (「파트 없음」 for an episode's part-less cuts; a
  /// storyboard's own name) and stage; a cut's number.
  static String _title(StatsNode n) {
    final label = n.label;
    if (n.level != StatsLevel.unit) return label ?? '';
    final board = n.children.any((c) => c.key.startsWith('cut:s'));
    final part = board
        ? label ?? ''
        : label == null
        ? S.noPart.t
        : S.partTitle.f({'p': label});
    return switch (n.stageName) {
      final stage? => '$part · ${stageText(stage)}',
      null => part,
    };
  }

  Widget _row(BuildContext context, StatsNode n, int depth, int shown) {
    final c = AppColors.of(context);
    final key = n.key;
    final open = _open.contains(key);
    final opens =
        n.children.isNotEmpty ||
        n.level == StatsLevel.cut ||
        shown < StatsColumn.values.length;
    return InkWell(
      key: Key('stats-row-$key'),
      onTap: opens
          ? () => setState(() => open ? _open.remove(key) : _open.add(key))
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
  /// stage time, timer runs, take and state.
  Widget _openLine(BuildContext context, StatsNode n, int depth, int shown) {
    final c = AppColors.of(context);
    final hidden = StatsColumn.values.skip(shown);
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
          // A cut: its stage and time, timer runs, take, pay and state.
          if (n.level == StatsLevel.cut)
            Wrap(
              spacing: 12,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (n.stageName case final stage?)
                  Row(
                    key: Key('stats-stage-$stage'),
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Dot(stageColor(stage)),
                      Text(
                        '${stageText(stage)}  ${formatWorked(n.worked)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                if (n.intervals case final runs?)
                  Text(
                    S.timerRuns.f({'n': runs}),
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                if (n.retakeRound case final take? when take > 1)
                  Text(
                    S.retakeRound.f({'n': take}),
                    style: TextStyle(fontSize: 11, color: c.retake),
                  ),
                if (n.status case final status?)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Dot(c.of(status)),
                      Text(status.label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
