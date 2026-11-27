/// Registering cuts in one go: what the register screen collects, and the
/// writes that turn it into an episode, a part, cuts and tasks.
library;

import '../models/cut_numbers.dart';
import '../services/catalogue_store.dart';

/// The cut grid before it is saved: a numbered run, minus missing
/// numbers, with some cuts split into lettered cuts and some pairs joined
/// as one shared cut (each keeps its own status).
class CutDraft {
  CutDraft({
    this.start = 1,
    this.count = 100,
    this.prefix = 'C',
    this.width = 3,
    Set<String>? removed,
    Map<String, int>? splits,
    Map<String, String>? shared,
  }) : removed = removed ?? {},
       splits = splits ?? {},
       shared = shared ?? {};

  int start;
  int count;
  final String prefix;
  final int width;

  /// Missing numbers (결번), kept on the grid crossed out.
  final Set<String> removed;

  /// Cut → how many lettered cuts it becomes (2 = A/B).
  final Map<String, int> splits;

  /// First cut → last cut of a shared pair (겸용).
  final Map<String, String> shared;

  String number(int n) => '$prefix${n.toString().padLeft(width, '0')}';

  /// The run's numbers, before anything is taken out.
  List<String> get run =>
      cutNumberRun(start: start, count: count, prefix: prefix, width: width);

  /// Cells shown on the grid: the run without the second halves of
  /// shared pairs.
  List<String> get cells {
    final tails = shared.values.toSet();
    return [
      for (final n in run)
        if (!tails.contains(n)) n,
    ];
  }

  /// How many cuts will be saved.
  int get total {
    var t = 0;
    for (final n in cells) {
      if (removed.contains(n)) continue;
      t += splits[n] ?? 1;
      if (shared.containsKey(n)) t += 1;
    }
    return t;
  }

  /// Takes [picked] out, or puts them back when all were out.
  void toggleRemoved(Iterable<String> picked) {
    final all = picked.every(removed.contains);
    for (final n in picked) {
      all ? removed.remove(n) : removed.add(n);
    }
  }

  /// Splits [picked] into A/B, or undoes it when all were split.
  void toggleSplit(Iterable<String> picked) {
    final all = picked.every(splits.containsKey);
    for (final n in picked) {
      all ? splits.remove(n) : splits[n] = 2;
    }
  }

  /// Joins two picked cells, or parts a joined one.
  bool canShare(List<String> picked) =>
      picked.length == 2 ||
      (picked.length == 1 && shared.containsKey(picked.first));

  void toggleShared(List<String> picked) {
    if (picked.length == 1) {
      shared.remove(picked.first);
    } else if (picked.length == 2) {
      final p = [...picked]..sort();
      shared[p.first] = p.last;
    }
  }

  /// The label a cell shows.
  String label(String n) =>
      shared.containsKey(n) ? sharedCutNumber(n, shared[n]!) : n;
}

/// Everything the register screen asks for.
class RegistrationDraft {
  RegistrationDraft({
    this.workId,
    this.newWorkTitle,
    this.clientId,
    required this.episodeNumber,
    this.partLabel,
    required this.stages,
    required this.cuts,
    this.kickoffAt,
    this.dueAt,
  });

  /// An existing work, or null with [newWorkTitle] to create one.
  final int? workId;
  final String? newWorkTitle;
  final int? clientId;
  final String episodeNumber;

  /// Free text; empty or null leaves the cuts outside any part.
  final String? partLabel;

  /// Stage names to make work for, in order.
  final List<String> stages;
  final CutDraft cuts;
  final DateTime? kickoffAt;
  final DateTime? dueAt;
}

/// Saves [d]: the work (when new), the episode (reused when its number
/// exists), the part, the cuts, a task per cut and stage, the splits and
/// shared pairs, and the kickoff and deadline. Returns the new task ids.
List<int> register(CatalogueStore store, RegistrationDraft d) {
  if (d.stages.isEmpty) throw ArgumentError('No stage picked.');
  final workId =
      d.workId ??
      store.createWork(
        (d.newWorkTitle ?? '').trim().isEmpty ? '새 작품' : d.newWorkTitle!.trim(),
        clientId: d.clientId,
      );
  final ep =
      store
          .episodes(workId)
          .where((e) => e.number == d.episodeNumber)
          .map((e) => e.id)
          .firstOrNull ??
      store.addEpisode(workId, d.episodeNumber);
  final label = d.partLabel?.trim() ?? '';
  final numbers = [
    for (final n in d.cuts.run)
      if (!d.cuts.removed.contains(n)) n,
  ];
  final partId = label.isEmpty
      ? null
      : store.addPart(ep, label, plannedCutCount: numbers.length);
  store.addCuts(ep, numbers, partId: partId);
  final idOf = {for (final c in store.cuts(ep)) c.number: c.id};
  final cutIds = [for (final n in numbers) ?idOf[n]];

  final tasks = <int>[];
  final stageIds = <int>[];
  for (final name in d.stages) {
    final found = store.stages(workId).where((s) => s.name == name);
    final stage = found.isEmpty ? store.addStage(workId, name) : found.first.id;
    stageIds.add(stage);
    if (partId != null) {
      tasks.addAll(store.addTasksForPart(partId, stage));
    } else {
      for (final c in cutIds) {
        tasks.add(store.addTask(stage, cutId: c));
      }
    }
  }
  for (final MapEntry(key: n, value: parts) in d.cuts.splits.entries) {
    final id = idOf[n];
    if (id == null || d.cuts.removed.contains(n) || parts < 2) continue;
    store.splitCut(id, [
      for (var i = 0; i < parts; i++) String.fromCharCode(65 + i),
    ]);
  }
  for (final MapEntry(key: a, value: b) in d.cuts.shared.entries) {
    final ia = idOf[a];
    final ib = idOf[b];
    if (ia == null || ib == null) continue;
    store.linkSharedCuts([ia, ib]);
  }
  final kickoff = d.kickoffAt ?? store.clock();
  if (partId != null) {
    for (final s in stageIds) {
      store.setPartSchedule(partId, s, kickoffAt: kickoff, dueAt: d.dueAt);
    }
  } else {
    for (final t in store.partGroups().expand((g) => g.tasks)) {
      if (!tasks.contains(t.id)) continue;
      store.setTaskKickoff(t.id, kickoff);
      if (d.dueAt != null) store.setTaskDue(t.id, d.dueAt);
    }
  }
  return tasks;
}
