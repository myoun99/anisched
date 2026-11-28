/// The same cuts at several stages (a part's LO and 原画) shown as one
/// card: the one rule the list (and any other view) bundles units by.
library;

import '../models/progress.dart';

/// Units that are the same cuts at different stages, in stage order.
class UnitBundle {
  UnitBundle(this.stages) : assert(stages.isNotEmpty);

  /// The member units, one per stage, in stage order.
  final List<PartGroup> stages;

  /// The first member's key stands for the bundle.
  String get key => stages.length == 1 ? stages.first.key : 'bundle:$_cuts';

  String get _cuts => bundleKeyOf(stages.first);

  bool get single => stages.length == 1;

  /// The stage whose deadline speaks for the bundle (D, pace, signal):
  /// the earliest deadline among stages with cuts still to work on (done
  /// but unsent cuts are not work); with none left, the first stage.
  PartGroup get lead {
    PartGroup? best;
    for (final g in stages) {
      if (!g.tasks.any((t) => t.status.needsWork)) continue;
      if (best == null) {
        best = g;
        continue;
      }
      final a = g.dueAt;
      final b = best.dueAt;
      if (a != null && (b == null || a.isBefore(b))) best = g;
    }
    return best ?? stages.first;
  }

  /// Every stage's tasks as one unit (picking, the summed bar).
  PartGroup get together => PartGroup([for (final g in stages) ...g.tasks]);

  /// Every member's cuts handed / every member's cuts.
  int get handed => stages.fold(0, (n, g) => n + g.handed);
  int get total => stages.fold(0, (n, g) => n + g.total);
}

/// What makes units "the same cuts": one part; an episode's part-less
/// cuts; a storyboard stays alone.
String bundleKeyOf(PartGroup g) => switch (g.kind) {
  GroupKind.part => 'part:${g.partId}',
  GroupKind.noPart => 'nopart:${g.episodeId}',
  GroupKind.storyboard => g.key,
};

/// [units] (already filtered and ordered) bundled by [bundleKeyOf]. A
/// bundle sits where its [UnitBundle.lead] was; its members go in stage
/// order.
List<UnitBundle> bundleUnits(List<PartGroup> units) {
  final byKey = <String, List<PartGroup>>{};
  for (final g in units) {
    (byKey[bundleKeyOf(g)] ??= []).add(g);
  }
  final at = {for (final (i, g) in units.indexed) g.key: i};
  return [
    for (final list in byKey.values)
      UnitBundle(list..sort((a, b) => a.stageId.compareTo(b.stageId))),
  ]..sort((a, b) => at[a.lead.key]!.compareTo(at[b.lead.key]!));
}
