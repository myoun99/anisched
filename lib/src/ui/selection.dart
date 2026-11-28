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
    final n = g.tasks.where((t) => _ids.contains(t.id)).length;
    return n == 0 ? Picked.none : (n == g.total ? Picked.all : Picked.some);
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

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}

/// The statuses a picked set can be moved to, in the bar's order.
const pickActions = [
  TaskStatus.inProgress,
  TaskStatus.done,
  TaskStatus.submitted,
];
