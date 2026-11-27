/// One stretch of tracked work: a start instant and, once stopped, a stop
/// instant. Elapsed time is never stored — it is always derived from these
/// two instants, so killing and relaunching the app mid-timer loses nothing.
class WorkInterval {
  const WorkInterval({
    required this.id,
    required this.start,
    this.stop,
    this.taskId,
  });

  final int id;

  /// The task this time was spent on, if any.
  final int? taskId;

  /// UTC instant the timer started.
  final DateTime start;

  /// UTC instant the timer stopped, or null while it is still running.
  final DateTime? stop;

  bool get isRunning => stop == null;

  /// Time worked in this interval as of [now]. A running interval counts up
  /// to [now]. Never negative, even if the clock moved backwards.
  Duration elapsed(DateTime now) => elapsedWithin(start, now, now);

  /// The part of this interval that falls inside `[from, to)`, as of [now].
  /// Used to split work that crosses midnight or a billing-period boundary.
  Duration elapsedWithin(DateTime from, DateTime to, DateTime now) {
    final end = stop ?? now;
    final lo = start.isAfter(from) ? start : from;
    final hi = end.isBefore(to) ? end : to;
    return hi.isAfter(lo) ? hi.difference(lo) : Duration.zero;
  }
}

/// Sum of [intervals] as of [now], optionally clipped to `[from, to)`.
Duration totalElapsed(
  Iterable<WorkInterval> intervals,
  DateTime now, {
  DateTime? from,
  DateTime? to,
}) {
  var total = Duration.zero;
  for (final i in intervals) {
    total += (from == null && to == null)
        ? i.elapsed(now)
        : i.elapsedWithin(from ?? i.start, to ?? (i.stop ?? now), now);
  }
  return total;
}
