/// Laying schedule bars out on a calendar with a limited number of
/// parallel lanes. Pure Dart.
library;

/// One bar: a schedule unit's [key] over local dates [start]..[end]
/// (both included).
class Span {
  Span(this.key, DateTime start, DateTime end)
    : start = _date(start),
      end = _date(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('A span cannot end before it starts: $key.');
    }
  }

  final String key;
  final DateTime start;
  final DateTime end;
}

DateTime _date(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  return DateTime.utc(l.year, l.month, l.day);
}

/// Where each bar goes and where the lanes run out.
class LaneLayout {
  const LaneLayout({
    required this.spans,
    required this.laneOf,
    required this.lanes,
    required this.busyDays,
    this.pinned = const {},
    this.overlapping = const {},
  });

  /// Bars the user pinned to a lane.
  final Set<String> pinned;

  /// Pinned bars that overlap another bar in their lane — kept there all
  /// the same (a bar never moves by itself); the view marks them.
  final Set<String> overlapping;

  /// The bars laid out, in placement order.
  final List<Span> spans;

  /// The lane (0-based) of each bar. Lanes at or past [lanes] are over
  /// the limit.
  final Map<String, int> laneOf;

  /// The parallel-work limit the layout was made for.
  final int lanes;

  /// How many bars run on each day that has any, oldest first.
  final List<({DateTime day, int count})> busyDays;

  /// Lanes actually used (may exceed [lanes]).
  int get usedLanes => laneOf.values.fold(0, (a, l) => l + 1 > a ? l + 1 : a);

  /// Bars placed past the limit.
  Set<String> get overflow => {
    for (final e in laneOf.entries)
      if (e.value >= lanes) e.key,
  };

  /// Runs of consecutive days with more bars than [lanes].
  List<({DateTime start, DateTime end})> get overflowRanges {
    final out = <({DateTime start, DateTime end})>[];
    DateTime? from;
    DateTime? last;
    for (final d in busyDays) {
      final over = d.count > lanes;
      final contiguous = last != null && d.day.difference(last).inDays == 1;
      if (over && from != null && contiguous) {
        last = d.day;
        continue;
      }
      if (from != null) out.add((start: from, end: last!));
      from = over ? d.day : null;
      last = d.day;
    }
    if (from != null) out.add((start: from, end: last!));
    return out;
  }
}

/// Lays [spans] out on lanes — the calendar's one placement rule (the
/// views keep no copy):
///
/// 1. Bars in [pinned] (key → lane: dragged there, or held where they
///    were placed) go to their lane first and stay there even when they
///    overlap another pinned bar ([LaneLayout.overlapping] — 유저
///    2026-11-28: a bar never moves by itself). Only a pin past the lane
///    count overflows.
/// 2. The rest, earliest start first (longer first, then key, on ties),
///    go into the first lane with room — no bar there overlapping it.
///    Without pins this is "after the lane's last bar ends".
/// 3. A bar with no room in any of the [lanes] lanes overflows.
///
/// Overflowing bars are still placed, on lanes past the limit, and show
/// up in [LaneLayout.overflow].
LaneLayout layoutLanes(
  List<Span> spans,
  int lanes, {
  Map<String, int> pinned = const {},
}) {
  if (lanes < 1) throw ArgumentError.value(lanes, 'lanes');
  int byStart(Span a, Span b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    final d = b.end.compareTo(a.end);
    return d != 0 ? d : a.key.compareTo(b.key);
  }

  final rows = <List<Span>>[];
  bool fits(int lane, Span s) {
    while (rows.length <= lane) {
      rows.add([]);
    }
    return rows[lane].every(
      (o) => o.end.isBefore(s.start) || o.start.isAfter(s.end),
    );
  }

  final laneOf = <String, int>{};
  void put(Span s, int lane) {
    rows[lane].add(s);
    laneOf[s.key] = lane;
  }

  void overflowPut(Span s) {
    var lane = lanes;
    while (!fits(lane, s)) {
      lane++;
    }
    put(s, lane);
  }

  final pins = [
    for (final s in spans)
      if (pinned.containsKey(s.key)) s,
  ]..sort(byStart);
  final overlapping = <String>{};
  for (final s in pins) {
    final lane = pinned[s.key]!;
    if (lane >= 0 && lane < lanes) {
      if (!fits(lane, s)) {
        overlapping.add(s.key);
        for (final o in rows[lane]) {
          if (!(o.end.isBefore(s.start) || o.start.isAfter(s.end))) {
            overlapping.add(o.key);
          }
        }
      }
      put(s, lane);
    } else {
      overflowPut(s);
    }
  }
  final rest = [
    for (final s in spans)
      if (!pinned.containsKey(s.key)) s,
  ]..sort(byStart);
  for (final s in rest) {
    var lane = 0;
    while (lane < lanes && !fits(lane, s)) {
      lane++;
    }
    if (lane < lanes) {
      put(s, lane);
    } else {
      overflowPut(s);
    }
  }
  final sorted = [...pins, ...rest];
  // Busy days by a sweep over start/end+1 events.
  final delta = <DateTime, int>{};
  for (final s in spans) {
    delta[s.start] = (delta[s.start] ?? 0) + 1;
    final after = s.end.add(const Duration(days: 1));
    delta[after] = (delta[after] ?? 0) - 1;
  }
  final days = delta.keys.toList()..sort();
  final busy = <({DateTime day, int count})>[];
  var running = 0;
  for (var i = 0; i < days.length; i++) {
    running += delta[days[i]]!;
    if (running == 0 || i + 1 == days.length) continue;
    for (
      var d = days[i];
      d.isBefore(days[i + 1]);
      d = d.add(const Duration(days: 1))
    ) {
      busy.add((day: d, count: running));
    }
  }
  return LaneLayout(
    spans: sorted,
    laneOf: laneOf,
    lanes: lanes,
    busyDays: busy,
    pinned: {for (final s in pins) s.key},
    overlapping: overlapping,
  );
}

/// Which dates a calendar bar spans.
enum CalendarBasis {
  /// The production schedule: kickoff to deadline.
  production,

  /// The user's real work: planned start to planned end, falling back to
  /// the kickoff and the deadline where the plan is empty (as the pace
  /// does).
  work,
}
