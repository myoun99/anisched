/// What the picked-task actions write: holds (대기), pulling work
/// (引き上げ) and deadlines, decided here so the widgets only ask and show.
library;

import '../models/progress.dart';
import '../services/catalogue_store.dart';

/// Where a unit's deadline lives: the part × stage, or each task's own
/// (loose cuts, a storyboard).
List<DueTarget> dueTargets(PartGroup g) => g.kind == GroupKind.part
    ? [DueTarget.part(g.partId!, g.stageId)]
    : [for (final t in g.tasks) DueTarget.task(t.id)];

/// A hold to write: whole parts (so cuts added later follow) and loose
/// tasks, put on hold or — when every picked open task already waits —
/// taken off.
class HoldPlan {
  const HoldPlan({
    required this.release,
    required this.parts,
    required this.loose,
  });

  /// Takes the hold off instead of putting it on.
  final bool release;

  /// Parts whose every open task is picked: (part, stage, its open tasks).
  final List<({int partId, int stageId, List<int> taskIds})> parts;

  /// Picked open tasks outside those parts.
  final Set<int> loose;

  bool get isEmpty => parts.isEmpty && loose.isEmpty;

  /// Plans a hold for [picked] over the units in [groups]. Done or handed
  /// tasks never wait, so they are left out.
  factory HoldPlan.of(Iterable<PartGroup> groups, Iterable<TaskRow> picked) {
    final open = [
      for (final t in picked)
        if (t.status.isOpen) t,
    ];
    final ids = {for (final t in open) t.id};
    final loose = {...ids};
    final parts = <({int partId, int stageId, List<int> taskIds})>[];
    for (final g in groups) {
      if (g.kind != GroupKind.part) continue;
      final own = [
        for (final t in g.tasks)
          if (t.status.isOpen) t.id,
      ];
      if (own.isEmpty || !own.every(ids.contains)) continue;
      parts.add((partId: g.partId!, stageId: g.stageId, taskIds: own));
      loose.removeAll(own);
    }
    return HoldPlan(
      release: open.isNotEmpty && open.every((t) => t.waiting),
      parts: parts,
      loose: loose,
    );
  }

  /// Writes the plan. Taking a hold off clears its reason and expected
  /// day in the store, whatever is passed.
  void apply(CatalogueStore store, {String? reason, DateTime? until}) {
    for (final p in parts) {
      store.setPartWaiting(
        p.partId,
        p.stageId,
        waiting: !release,
        reason: reason,
        until: until,
      );
      // The part's setting decides; drop the cuts' own.
      store.followPartWaiting(p.taskIds);
    }
    if (loose.isNotEmpty) {
      store.setWaitingMany(
        loose,
        waiting: !release,
        reason: reason,
        until: until,
      );
    }
  }
}

/// Pulling picked work off the user, or bringing it back when every
/// picked task is already pulled.
({bool back, List<int> ids}) planHandOff(Iterable<TaskRow> picked) {
  final list = picked.toList();
  final back = list.isNotEmpty && list.every((t) => t.handedOff);
  return (
    back: back,
    ids: [
      for (final t in list)
        if (t.handedOff == back) t.id,
    ],
  );
}
