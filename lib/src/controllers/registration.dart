/// Registering cuts in one go: what the register screen collects, and the
/// writes that turn it into a part, cuts and tasks.
library;

import '../models/cut_numbers.dart';
import '../services/catalogue_store.dart';

/// The cut grid before it is saved. Cells are a numbered run plus cuts
/// added by name; any cell can be renamed, left out (missing number),
/// split into lettered cuts, or paired with another as a shared cut.
/// A shared pair stays two cuts — it is only marked as one.
class CutDraft {
  CutDraft({
    this.start = 1,
    this.count = 100,
    this.prefix = 'C',
    this.width = 3,
  });

  int start;
  int count;
  final String prefix;
  final int width;

  /// Cuts added one by one, by name, after the run.
  final extras = <String>[];

  /// Cell → the name the user gave it.
  final renames = <String, String>{};

  /// Missing numbers (결번), kept on the grid crossed out.
  final removed = <String>{};

  /// Cell → how many lettered cuts it becomes (2 = A/B).
  final splits = <String, int>{};

  /// First cell → second cell of a shared pair (겸용).
  final shared = <String, String>{};

  String number(int n) => '$prefix${n.toString().padLeft(width, '0')}';

  /// Cell ids in grid order: the run, then the added cuts.
  List<String> get cells => [
    ...cutNumberRun(start: start, count: count, prefix: prefix, width: width),
    for (final e in extras)
      if (!_inRun(e)) e,
  ];

  bool _inRun(String id) {
    final m = RegExp(r'^(\D*)(\d+)$').firstMatch(id);
    if (m == null || m[1] != prefix || m[2]!.length != width) return false;
    final n = int.parse(m[2]!);
    return n >= start && n < start + count;
  }

  /// The cut number a cell will be saved as.
  String nameOf(String id) => renames[id] ?? id;

  /// How many cuts will be saved.
  int get total => [
    for (final c in cells)
      if (!removed.contains(c)) splits[c] ?? 1,
  ].fold(0, (a, b) => a + b);

  /// Cells whose name is used twice on the grid or already [taken]; names
  /// are compared by [key] (the store compares stored values).
  Set<String> clashes([
    Set<String> taken = const {},
    String Function(String name) key = _same,
  ]) {
    final seen = <String, String>{};
    final out = <String>{};
    for (final c in cells) {
      if (removed.contains(c)) continue;
      final n = key(nameOf(c));
      if (taken.contains(n)) out.add(c);
      final other = seen[n];
      if (other != null) out.addAll([c, other]);
      seen[n] = c;
    }
    return out;
  }

  /// The other cell of [id]'s shared pair, if any.
  String? partner(String id) {
    if (shared.containsKey(id)) return shared[id];
    for (final e in shared.entries) {
      if (e.value == id) return e.key;
    }
    return null;
  }

  /// What a cell shows: its name; the first of a shared pair shows the
  /// pair (`C004-005`).
  String label(String id) {
    final tail = shared[id];
    return tail == null
        ? nameOf(id)
        : sharedCutNumber(nameOf(id), nameOf(tail));
  }

  /// Adds a cut by name at the end. False if the name is empty.
  bool add(String name) {
    final n = name.trim();
    if (n.isEmpty) return false;
    extras.add(n);
    return true;
  }

  void rename(String id, String name) {
    final n = name.trim();
    if (n.isEmpty || n == id) {
      renames.remove(id);
    } else {
      renames[id] = n;
    }
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

  /// Two picked cells can be paired; one paired cell can be unpaired.
  bool canShare(List<String> picked) =>
      (picked.length == 2 && picked.every((p) => partner(p) == null)) ||
      (picked.length == 1 && partner(picked.first) != null);

  void toggleShared(List<String> picked) {
    if (picked.length == 1) {
      final p = picked.first;
      shared.remove(p);
      shared.removeWhere((_, v) => v == p);
    } else if (picked.length == 2) {
      final order = cells;
      final p = [...picked]
        ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
      shared[p.first] = p.last;
    }
  }
}

/// Everything the register screen asks for. The client, work and
/// episode are picked (or made) before this.
class RegistrationDraft {
  RegistrationDraft({
    required this.workId,
    required this.episodeId,
    this.partLabel,
    required this.stages,
    required this.cuts,
    this.kickoffAt,
    this.dueAt,
    this.schedules = const {},
  });

  final int workId;
  final int episodeId;

  /// Free text; an existing part of that label is reused; empty or null
  /// leaves the cuts outside any part.
  final String? partLabel;

  /// Stage names to make work for, in order.
  final List<String> stages;
  final CutDraft cuts;
  final DateTime? kickoffAt;
  final DateTime? dueAt;

  /// Each stage's own production start and deadline (LO and 原画 rarely
  /// share them), by stage name; a stage missing here, or a date left
  /// null, takes [kickoffAt] / [dueAt].
  final Map<String, ({DateTime? kickoffAt, DateTime? dueAt})> schedules;

  DateTime? kickoffOf(String stage) => schedules[stage]?.kickoffAt ?? kickoffAt;
  DateTime? dueOf(String stage) => schedules[stage]?.dueAt ?? dueAt;
}

/// Thrown when cut names clash with each other or with the episode.
class CutNameClash implements Exception {
  CutNameClash(this.names);

  final List<String> names;

  @override
  String toString() => 'CutNameClash: ${names.join(', ')}';
}

/// Saves [d]: the part, the cuts, a task per cut and stage, the splits
/// and shared pairs, and the kickoff and deadline. Returns the new task
/// ids. Clashing names change nothing and throw [CutNameClash].
List<int> register(CatalogueStore store, RegistrationDraft d) {
  if (d.stages.isEmpty) throw ArgumentError('No stage picked.');
  final ep = d.episodeId;
  // Numbers are matched by value: what the grid names `C012` is the cut
  // stored as 12, whatever the style.
  final taken = {for (final c in store.cuts(ep)) store.cutKey(c.number)};
  final clash = d.cuts.clashes(taken, store.cutKey);
  if (clash.isNotEmpty) {
    throw CutNameClash([for (final c in clash) d.cuts.nameOf(c)]);
  }
  final live = [
    for (final c in d.cuts.cells)
      if (!d.cuts.removed.contains(c)) c,
  ];
  final label = d.partLabel?.trim() ?? '';
  final partId = label.isEmpty
      ? null
      : store
                .parts(ep)
                .where((p) => p.label == label)
                .map((p) => p.id)
                .firstOrNull ??
            store.addPart(ep, label, plannedCutCount: live.length);
  final added = store.addCuts(ep, [
    for (final c in live) d.cuts.nameOf(c),
  ], partId: partId).added;
  final idOf = {for (final c in store.cuts(ep)) store.cutKey(c.number): c.id};
  final cellId = {
    for (final c in live) c: idOf[store.cutKey(d.cuts.nameOf(c))],
  };

  final tasks = <int>[];
  final stageIds = <int>[];
  final tasksOf = <String, List<int>>{};
  for (final name in d.stages) {
    final found = store.stages(d.workId).where((s) => s.name == name);
    final stage = found.isEmpty
        ? store.addStage(d.workId, name)
        : found.first.id;
    stageIds.add(stage);
    final own = tasksOf[name] = [
      for (final c in added) store.addTask(stage, cutId: c),
    ];
    tasks.addAll(own);
  }
  for (final MapEntry(key: c, value: parts) in d.cuts.splits.entries) {
    final id = cellId[c];
    if (id == null || parts < 2) continue;
    store.splitCut(id, [
      for (var i = 0; i < parts; i++) String.fromCharCode(65 + i),
    ]);
  }
  for (final MapEntry(key: a, value: b) in d.cuts.shared.entries) {
    final ia = cellId[a];
    final ib = cellId[b];
    if (ia != null && ib != null) store.linkSharedCuts([ia, ib]);
  }
  // Each stage's own dates: on its part × stage, or on each of its tasks
  // for cuts outside a part.
  for (final (i, name) in d.stages.indexed) {
    final kickoff = d.kickoffOf(name) ?? store.clock();
    final due = d.dueOf(name);
    if (partId != null) {
      store.setPartSchedule(
        partId,
        stageIds[i],
        kickoffAt: kickoff,
        dueAt: due,
      );
      continue;
    }
    final mine = tasksOf[name]!.toSet();
    for (final g in store.partGroups()) {
      if (g.stageId != stageIds[i]) continue;
      for (final t in g.tasks) {
        if (!mine.contains(t.id)) continue;
        store.setTaskKickoff(t.id, kickoff);
        if (due != null) store.setTaskDue(t.id, due);
      }
    }
  }
  return tasks;
}

String _same(String name) => name;
