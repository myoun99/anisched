import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../format.dart';
import '../part_line.dart';
import '../selection.dart';
import '../theme.dart';
import '../widgets.dart';

/// What the board's columns sort parts by. Easy to add to: a basis is a
/// label plus columns, each a name and a test.
enum BoardBasis {
  due('마감 순'),
  plan('계획 순'),
  status('상태 순');

  const BoardBasis(this.label);

  final String label;
}

typedef _Column = ({
  String label,
  bool Function(PartGroup g, GroupSignals? s) test,
});

List<_Column> _columns(BoardBasis b, {required bool showDone}) {
  bool handed(GroupSignals? s) => s?.due is DueSubmitted || s?.due is DueDone;
  int? daysLeft(GroupSignals? s) => switch (s?.due) {
    DueDaysLeft(:final days) => days,
    _ => null,
  };
  return switch (b) {
    BoardBasis.due => [
      (label: '지난 것', test: (_, s) => s?.due is DueLate),
      (label: '3일 안', test: (_, s) => (daysLeft(s) ?? 99) <= 3),
      (
        label: '2주 안',
        test: (_, s) {
          final d = daysLeft(s);
          return d != null && d > 3 && d <= 14;
        },
      ),
      (
        label: '그 뒤',
        test: (_, s) =>
            (daysLeft(s) ?? 0) > 14 || (s == null || s.due is DueNone),
      ),
      (label: '넘김', test: (_, s) => handed(s)),
    ],
    BoardBasis.plan => [
      (label: '지금', test: (_, s) => !handed(s) && s?.plan is! PlanNotStarted),
      (label: '시작 전', test: (_, s) => !handed(s) && s?.plan is PlanNotStarted),
      (label: '넘김', test: (_, s) => handed(s)),
    ],
    BoardBasis.status => [
      for (final st in TaskStatus.values)
        if (showDone || st != TaskStatus.done)
          (label: st.label, test: (g, _) => g.status == st),
    ],
  };
}

/// Cards in columns, by deadline urgency unless another basis is chosen.
/// A card shows only the part, its work, progress and the D slot; tapping
/// opens the rest under it.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.parts,
    required this.layout,
    this.signals = const {},
    this.paces = const {},
    this.selection,
    this.showDone = false,
    this.onShowDoneChanged,
  });

  final List<PartGroup> parts;
  final ScreenLayout layout;
  final Map<String, GroupSignals> signals;
  final Map<String, StagePace> paces;
  final TaskSelection? selection;
  final bool showDone;
  final ValueChanged<bool>? onShowDoneChanged;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  BoardBasis _basis = BoardBasis.due;

  /// The narrow layout's column; null = the first one with cards.
  int? _tab;
  final _expanded = <String>{};

  List<(String, List<PartGroup>)> get _filled {
    final cols = _columns(_basis, showDone: widget.showDone);
    final sorted = [...widget.parts]
      ..sort(
        (a, b) =>
            (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999)),
      );
    return [
      for (final col in cols)
        (
          col.label,
          [
            for (final g in sorted)
              if (col.test(g, widget.signals[g.key])) g,
          ],
        ),
    ];
  }

  void _tap(PartGroup g) {
    final sel = widget.selection;
    if (sel != null && !sel.isEmpty) {
      sel.toggleGroup(g);
      return;
    }
    setState(() {
      if (!_expanded.remove(g.key)) _expanded.add(g.key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cols = _filled;
    final narrow = widget.layout.size == SizeClass.narrow;
    var tab = _tab ?? cols.indexWhere((c) => c.$2.isNotEmpty);
    if (tab < 0 || tab >= cols.length) tab = 0;
    final toolbar = ViewToolbar(
      children: [
        PopupMenuButton<BoardBasis>(
          key: const Key('board-basis'),
          tooltip: '',
          onSelected: (b) => setState(() {
            _basis = b;
            _tab = null;
          }),
          itemBuilder: (_) => [
            for (final b in BoardBasis.values)
              PopupMenuItem(value: b, child: Text(b.label)),
          ],
          child: ToolbarButton(
            label: _basis.label,
            selected: false,
            dropdown: true,
          ),
        ),
        ToolbarButton(
          key: const Key('board-done'),
          label: widget.showDone ? '완료 보임' : '완료 숨김',
          selected: widget.showDone,
          onTap: widget.onShowDoneChanged == null
              ? null
              : () => widget.onShowDoneChanged!(!widget.showDone),
        ),
      ],
    );
    return ColoredBox(
      color: c.panelAlt,
      child: ListenableBuilder(
        listenable: widget.selection ?? Listenable.merge(const []),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: c.panel, child: toolbar),
            if (narrow) ...[
              _Tabs(
                labels: [for (final (l, list) in cols) '$l ${list.length}'],
                current: tab,
                onTap: (i) => setState(() => _tab = i),
              ),
              Expanded(child: _cardList(cols[tab].$2)),
            ] else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: widget.layout.size == SizeClass.wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            for (final (l, list) in cols)
                              Expanded(child: _column(l, list)),
                          ],
                        )
                      : OwnScroll(
                          builder: (controller) => ListView(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final (l, list) in cols)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 230,
                                    child: _column(l, list),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _column(String label, List<PartGroup> list) {
    final c = AppColors.of(context);
    return DecoratedBox(
      key: Key('column-$label'),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text('${list.length}', style: TextStyle(color: c.muted)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(child: _cardList(list)),
        ],
      ),
    );
  }

  Widget _cardList(List<PartGroup> list) => OwnScroll(
    builder: (controller) => ListView.separated(
      controller: controller,
      padding: const EdgeInsets.all(8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final g = list[i];
        final sel = widget.selection;
        final picking = sel != null && !sel.isEmpty;
        return _Card(
          group: g,
          signals: widget.signals[g.key],
          expanded: _expanded.contains(g.key),
          picked: sel?.of(g) ?? Picked.none,
          onTap: () => _tap(g),
          onLongPress: sel == null ? null : () => sel.toggleGroup(g),
          details: PartDetails(
            group: g,
            pace: widget.signals[g.key]?.pace,
            plan: widget.signals[g.key]?.plan,
            usual: widget.paces[g.stageName],
            isPicked: sel?.has,
            onTask: picking ? sel.toggleTask : null,
          ),
        );
      },
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.group,
    required this.signals,
    required this.expanded,
    required this.picked,
    required this.onTap,
    required this.onLongPress,
    required this.details,
  });

  final PartGroup group;
  final GroupSignals? signals;
  final bool expanded;
  final Picked picked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = group;
    final fill = switch (picked) {
      Picked.all => c.selected,
      Picked.some => Color.lerp(c.panelAlt, c.selected, 0.5)!,
      Picked.none => c.panelAlt,
    };
    final fade =
        signals?.plan is PlanNotStarted &&
        planTone(signals!.plan) == PlanTone.none;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: picked == Picked.none ? c.line : fill),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: fill,
              child: InkWell(
                key: Key('card-${g.key}'),
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 6,
                    children: [
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: groupTitle(g),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${g.stageName}',
                                    style: TextStyle(color: c.muted),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (signals != null)
                            SignalLabel(due: signals!.due, plan: signals!.plan),
                        ],
                      ),
                      Row(
                        spacing: 6,
                        children: [
                          Expanded(
                            child: Text(
                              '${g.workTitle} ${g.episodeNumber}',
                              style: TextStyle(fontSize: 12, color: c.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: PartProgress(g, height: 4),
                          ),
                          Text(
                            '${g.handed}/${g.total}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) details,
          ],
        ),
      ),
    );
    return fade ? Opacity(opacity: 0.5, child: card) : card;
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.current,
    required this.onTap,
  });

  final List<String> labels;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ColoredBox(
      color: c.panel,
      child: SizedBox(
        height: 50,
        child: OwnScroll(
          builder: (controller) => ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ToolbarButton(
                    key: Key('board-tab-$i'),
                    label: labels[i],
                    selected: i == current,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
