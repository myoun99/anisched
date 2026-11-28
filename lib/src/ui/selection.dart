import 'package:flutter/foundation.dart';

import '../models/catalogue.dart';
import '../models/progress.dart';

/// How much of a group is picked.
enum Picked { none, some, all }

/// The tasks the user has picked across all four views, for one action at
/// a time (submit, done, …). A long press on a group picks or drops all of
/// its tasks; once anything is picked, taps pick too.
class TaskSelection extends ChangeNotifier {
  final _ids = <int>{};

  Set<int> get ids => Set.unmodifiable(_ids);
  int get count => _ids.length;
  bool get isEmpty => _ids.isEmpty;

  Picked of(PartGroup g) {
    // Tasks, not [PartGroup.total] (a shared group counts once there).
    final n = g.tasks.where((t) => _ids.contains(t.id)).length;
    return n == 0
        ? Picked.none
        : (n == g.tasks.length ? Picked.all : Picked.some);
  }

  bool has(TaskRow t) => _ids.contains(t.id);

  /// Picks every task of [g], or drops them all if all were picked.
  void toggleGroup(PartGroup g) {
    if (of(g) == Picked.all) {
      _ids.removeAll(g.tasks.map((t) => t.id));
    } else {
      _ids.addAll(g.tasks.map((t) => t.id));
    }
    notifyListeners();
  }

  void toggleTask(TaskRow t) {
    if (!_ids.remove(t.id)) _ids.add(t.id);
    notifyListeners();
  }

  /// Picks one cut as shown — a shared (겸용) group's tasks together —
  /// or drops it if all of it was picked.
  void toggleUnit(List<TaskRow> unit) {
    if (unit.every(has)) {
      _ids.removeAll(unit.map((t) => t.id));
    } else {
      _ids.addAll(unit.map((t) => t.id));
    }
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}

/// The statuses a picked set can be moved to.
const pickActions = [
  TaskStatus.inProgress,
  TaskStatus.submitted,
  TaskStatus.retake,
  TaskStatus.received,
];

/// The picked-task bar's actions, most used first: as many as fit stand
/// on the bar with their words, the rest go under ⋯ (the user's order,
/// 2026-11-28). Status actions by their stored name.
const pickPriority = [
  'submitted',
  'edit',
  'share',
  'in_progress',
  'due',
  'hold',
  'retake',
  'received',
  'drop',
  'rename',
  'takeout',
  'archive',
  'delete',
];
