import 'package:flutter/material.dart';

import '../models/catalogue.dart';
import '../models/number_style.dart';
import '../models/progress.dart';
import 'client_chip.dart';
import 'fit_text.dart';
import 'format.dart';
import 'instant.dart';
import 'palette.dart';
import 'text/strings.dart';
import 'theme.dart';
import 'widgets.dart';

/// The levels of the catalogue, top down.
enum BrowseLevel { client, work, episode, unit, cut }

/// Where the browser is: the client (by name; null: none), work, episode
/// and unit picked so far.
typedef BrowsePath = ({
  String? client,
  int? work,
  int? episode,
  String? unit,
  int depth,
});

/// What was picked: a unit (a card), and at the cut level its cut (a
/// shared group's tasks; the first is the one to use).
typedef BrowsePick = ({PartGroup unit, List<TaskRow>? cut});

/// Opens the catalogue as a small page to walk down, one level a list —
/// 회사 → 작품 → 화 → 파트·공정 → 컷 — with the path on top and 「↑」
/// to go up, and a search that finds cuts from any level. Ends at [until]
/// (a cut for the timer; a unit for 「go to the card」). Starts at
/// [start] (deeper levels need the path to it).
Future<BrowsePick?> browseCatalogue(
  BuildContext context, {
  required List<PartGroup> groups,
  required ClientTag? Function(PartGroup g) clientOf,
  BrowseLevel until = BrowseLevel.cut,
  BrowsePath? start,
  NumberStyle? cutStyle,
  String? title,
}) => showInstantDialog<BrowsePick>(
  context: context,
  builder: (_) => CatalogueBrowser(
    groups: groups,
    clientOf: clientOf,
    until: until,
    start: start,
    cutStyle: cutStyle,
    title: title ?? S.cutName.t,
  ),
);

/// The path that opens the browser at [g]'s level [level] (its parents
/// picked).
BrowsePath browsePathTo(PartGroup g, BrowseLevel level) => (
  client: g.clientName,
  work: level.index > BrowseLevel.work.index ? g.workId : null,
  episode: level.index > BrowseLevel.episode.index ? g.episodeId : null,
  unit: level.index > BrowseLevel.unit.index ? g.key : null,
  depth: level.index,
);

class CatalogueBrowser extends StatefulWidget {
  const CatalogueBrowser({
    super.key,
    required this.groups,
    required this.clientOf,
    required this.title,
    this.until = BrowseLevel.cut,
    this.start,
    this.cutStyle,
  });

  final List<PartGroup> groups;
  final ClientTag? Function(PartGroup g) clientOf;
  final String title;
  final BrowseLevel until;
  final BrowsePath? start;
  final NumberStyle? cutStyle;

  @override
  State<CatalogueBrowser> createState() => _CatalogueBrowserState();
}

/// One line of a level: its key, what it shows, the cuts left under it.
typedef _Node = ({Object key, PartGroup sample, int left, List<TaskRow>? cut});

class _CatalogueBrowserState extends State<CatalogueBrowser> {
  late BrowsePath _at =
      widget.start ??
      (client: null, work: null, episode: null, unit: null, depth: 0);
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  BrowseLevel get _level => BrowseLevel.values[_at.depth];

  /// The groups under the path.
  Iterable<PartGroup> get _under => widget.groups.where(
    (g) =>
        (_at.depth < 1 || g.clientName == _at.client) &&
        (_at.work == null || g.workId == _at.work) &&
        (_at.episode == null || g.episodeId == _at.episode) &&
        (_at.unit == null || g.key == _at.unit),
  );

  static int _left(Iterable<TaskRow> tasks) =>
      cutUnits(tasks.where((t) => t.status.isOpen)).length;

  List<_Node> _nodes() {
    final under = _under.toList();
    if (_level == BrowseLevel.cut) {
      final g = under.firstOrNull;
      if (g == null) return const [];
      final units = cutUnits(
        sortedByCutNumber(g.tasks, taskLabel, widget.cutStyle),
      );
      return [
        for (final u in units)
          (key: u.first.id, sample: g, left: _left(u), cut: u),
      ];
    }
    final by = <Object, List<PartGroup>>{};
    for (final g in under) {
      final k = switch (_level) {
        BrowseLevel.client => g.clientName ?? '',
        BrowseLevel.work => g.workId,
        BrowseLevel.episode => g.episodeId,
        _ => g.key,
      };
      (by[k] ??= []).add(g);
    }
    final nodes = [
      for (final e in by.entries)
        (
          key: e.key,
          sample: e.value.first,
          left: _left(e.value.expand((g) => g.tasks)),
          cut: null,
        ),
    ];
    String name(_Node n) => switch (_level) {
      BrowseLevel.client => n.sample.clientName ?? '￿',
      BrowseLevel.work => n.sample.workTitle,
      BrowseLevel.episode => n.sample.episodeNumber,
      _ => '${n.sample.partLabel ?? ''} ${n.sample.stagePosition}',
    };
    return nodes..sort(
      (a, b) => naturalSortKey(name(a)).compareTo(naturalSortKey(name(b))),
    );
  }

  /// Cuts under the path whose name, title or episode holds the query.
  List<_Node> _found(String q) => [
    for (final g in _under)
      for (final u in cutUnits(
        sortedByCutNumber(g.tasks, taskLabel, widget.cutStyle),
      ))
        if (unitText(u).contains(q) ||
            g.workTitle.contains(q) ||
            g.episodeNumber.contains(q))
          (key: u.first.id, sample: g, left: _left(u), cut: u),
  ];

  void _open(_Node n) {
    if (n.cut != null) {
      Navigator.pop(context, (unit: n.sample, cut: n.cut));
      return;
    }
    if (_level == widget.until) {
      Navigator.pop(context, (unit: n.sample, cut: null));
      return;
    }
    final g = n.sample;
    setState(() {
      _at = switch (_level) {
        BrowseLevel.client => (
          client: g.clientName,
          work: null,
          episode: null,
          unit: null,
          depth: 1,
        ),
        BrowseLevel.work => (
          client: g.clientName,
          work: g.workId,
          episode: null,
          unit: null,
          depth: 2,
        ),
        BrowseLevel.episode => (
          client: g.clientName,
          work: g.workId,
          episode: g.episodeId,
          unit: null,
          depth: 3,
        ),
        _ => (
          client: g.clientName,
          work: g.workId,
          episode: g.episodeId,
          unit: g.key,
          depth: 4,
        ),
      };
    });
  }

  void _upTo(int depth) => setState(
    () => _at = (
      client: depth > 0 ? _at.client : null,
      work: depth > 1 ? _at.work : null,
      episode: depth > 2 ? _at.episode : null,
      unit: depth > 3 ? _at.unit : null,
      depth: depth,
    ),
  );

  /// The path's steps, each a button back to it.
  List<(int, String)> _crumbs() {
    final g = _under.firstOrNull;
    return [
      (0, S.client.t),
      if (_at.depth > 0) (1, _at.client ?? S.noClient.t),
      if (_at.depth > 1 && g != null) (2, g.workTitle),
      if (_at.depth > 2 && g != null) (3, g.episodeNumber),
      if (_at.depth > 3 && g != null) (4, unitTitle(g)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final q = _query.text.trim();
    final nodes = q.isEmpty ? _nodes() : _found(q);
    final crumbs = _crumbs();
    return AlertDialog(
      key: const Key('browser'),
      title: DialogTitle(Icons.folder_open_outlined, widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            TextField(
              key: const Key('browser-search'),
              controller: _query,
              onTapOutside: unfocusOutside,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
            Row(
              children: [
                IconButton(
                  key: const Key('browser-up'),
                  tooltip: '',
                  visualDensity: VisualDensity.compact,
                  onPressed: _at.depth == 0 ? null : () => _upTo(_at.depth - 1),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        for (final (i, (depth, name)) in crumbs.indexed) ...[
                          if (i > 0)
                            Icon(Icons.chevron_right, size: 14, color: c.faint),
                          InkWell(
                            key: Key('browser-crumb-$depth'),
                            onTap: depth == _at.depth
                                ? null
                                : () => _upTo(depth),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: depth == _at.depth ? null : c.muted,
                                  fontWeight: depth == _at.depth
                                      ? FontWeight.w700
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  key: const Key('browser-list'),
                  itemCount: nodes.length,
                  itemBuilder: (context, i) => _line(context, nodes[i], q),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.cancel.t),
        ),
      ],
    );
  }

  Widget _line(BuildContext context, _Node n, String q) {
    final c = AppColors.of(context);
    final g = n.sample;
    final cut = n.cut;
    final level = cut != null ? BrowseLevel.cut : _level;
    final name = switch (level) {
      BrowseLevel.client => switch (widget.clientOf(g)) {
        final tag? => Align(
          alignment: Alignment.centerLeft,
          child: ClientChip(tag),
        ),
        null => FitText(g.clientName ?? S.noClient.t),
      },
      BrowseLevel.work => FitText(g.workTitle),
      BrowseLevel.episode => FitText(g.episodeNumber),
      BrowseLevel.unit => Row(
        spacing: 6,
        children: [
          Dot(stageColor(g.stageName)),
          Flexible(child: FitText(unitTitle(g))),
        ],
      ),
      BrowseLevel.cut => Row(
        spacing: 8,
        children: [
          Text(
            unitText(cut!),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: c.ink(cut.first.status),
            ),
          ),
          // Found by search: where it is.
          if (q.isNotEmpty)
            Flexible(
              child: FitText(
                '${g.workTitle} ${g.episodeNumber} · ${unitTitle(g)}',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
        ],
      ),
    };
    final opens = cut == null && level != widget.until;
    return InkWell(
      key: Key('browse-${level.name}-${n.key}'),
      onTap: () => _open(n),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          spacing: 8,
          children: [
            Expanded(child: name),
            if (cut == null)
              Text(
                '${n.left}',
                style: TextStyle(
                  fontSize: 12,
                  color: n.left == 0 ? c.faint : c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            if (opens) Icon(Icons.chevron_right, size: 16, color: c.faint),
          ],
        ),
      ),
    );
  }
}

/// A unit's name: its part (「파트 없음」 for an episode's loose cuts; a
/// storyboard's own name) and stage.
String unitTitle(PartGroup g) {
  final part = switch (g.kind) {
    GroupKind.part => S.partTitle.f({'p': g.partLabel ?? ''}),
    GroupKind.noPart => S.noPart.t,
    _ => g.storyboardLabel ?? '',
  };
  return '$part · ${stageText(g.stageName)}';
}
