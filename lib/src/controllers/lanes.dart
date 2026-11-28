/// Adding, naming and removing the work view's lanes (라인). The lane
/// count is the 병행 수 setting; names and pins follow a removed lane.
library;

import '../models/lanes.dart';
import '../services/catalogue_store.dart';

/// The most lanes the settings keep.
const maxLanes = 20;

/// One more lane at the bottom, unnamed. False at [maxLanes].
bool addLane(CatalogueStore store) {
  final n = store.settings.parallelLanes;
  if (n >= maxLanes) return false;
  store.settings.parallelLanes = n + 1;
  return true;
}

/// Names lane [lane]; blank takes the name off (the view shows its
/// number).
void renameLane(CatalogueStore store, int lane, String? name) {
  final names = store.settings.laneNames;
  final n = name?.trim() ?? '';
  names[lane] = n.isEmpty ? null : n;
  store.settings.laneNames = names;
}

/// Removes lane [lane]: the lanes below move up with their names and
/// pins; work pinned to it goes back to automatic placement. The last
/// lane stays. False when nothing was removed.
bool removeLane(CatalogueStore store, LaneLayout layout, int lane) {
  final n = store.settings.parallelLanes;
  if (n <= 1 || lane < 0 || lane >= n) return false;
  final names = store.settings.laneNames..removeAt(lane);
  for (final key in layout.pinned) {
    final at = layout.laneOf[key];
    if (at == null) continue;
    if (at == lane) {
      store.unpinLane(key);
    } else if (at > lane) {
      store.pinLane(key, at - 1);
    }
  }
  store.settings.parallelLanes = n - 1;
  store.settings.laneNames = names;
  return true;
}
