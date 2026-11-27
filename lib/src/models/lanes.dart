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
  });

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
/// views keep no copy): earliest start first (longer first, then key, on
/// ties); each bar goes into the first lane whose last bar ends before the
/// bar starts; if none of the [lanes] lanes has room, the bar overflows.
/// Overflowing bars are still placed, on lanes past the limit, and show
/// up in [LaneLayout.overflow]. This uses as few lanes as the busiest day
/// needs.
LaneLayout layoutLanes(List<Span> spans, int lanes) {
  if (lanes < 1) throw ArgumentError.value(lanes, 'lanes');
  final sorted = [...spans]
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      final d = b.end.compareTo(a.end);
      return d != 0 ? d : a.key.compareTo(b.key);
    });
  final laneEnds = <DateTime>[];
  final laneOf = <String, int>{};
  for (final s in sorted) {
    var lane = laneEnds.indexWhere((end) => end.isBefore(s.start));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(s.end);
    } else {
      laneEnds[lane] = s.end;
    }
    laneOf[s.key] = lane;
  }
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
