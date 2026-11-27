/// Source of the current instant. Injected so time-dependent code can be
/// tested with a fixed clock instead of the wall clock.
typedef Clock = DateTime Function();

/// The wall clock, in UTC.
DateTime systemClock() => DateTime.now().toUtc();
