import 'holidays.dart';
import 'progress.dart';
import 'stats.dart';
import 'work_interval.dart';

/// One card due soon on the dashboard: its production deadline within the
/// window (or past), what is left and what today asks.
class DashboardDue {
  const DashboardDue({
    required this.group,
    required this.daysLeft,
    required this.pace,
  });

  final PartGroup group;

  /// Days to the production deadline (0 = today, negative = late).
  final int daysLeft;

  /// The card's pace ([paceFor], the pace-end setting) — the same value
  /// as the list card's "cuts a day".
  final Pace? pace;

  /// Cuts not yet worked through (received, in progress, retake).
  int get remaining =>
      pace?.remaining ??
      unitCount(group.tasks.where((t) => t.status.needsWork));

  /// What today asks of this card ([Pace.today]).
  double get perDay => pace?.today ?? 0;

  /// Past the deadline, or cuts left with no working day.
  bool get late => daysLeft < 0 || (pace?.behind ?? false);
}

/// The dashboard tab (유저 2026-11-28), read in one go: today, cards due
/// soon, today's and tomorrow's schedule, what needs attention, and this
/// week against the last. Every figure comes from the same reads as the
/// today list ([TodayView]), the signals ([GroupSignals]) and the
/// statistics ([StatsSlice]).
class Dashboard {
  const Dashboard({
    required this.day,
    required this.today,
    required this.todayStats,
    required this.running,
    required this.timerTarget,
    required this.dueSoon,
    required this.events,
    required this.holidays,
    required this.retakeCuts,
    required this.retakeCards,
    required this.waiting,
    required this.thisWeek,
    required this.lastWeek,
    required this.weekFrom,
  });

  /// The work day the dashboard is for (local date; the day start
  /// setting decides when it turns).
  final DateTime day;

  // ---- today ----

  /// The today list: [TodayView.cutsToday] is the cuts every open card
  /// asks of today, summed; [TodayView.late] the late count.
  final TodayView today;

  /// Today as a statistics range: [StatsSlice.handed] the cuts handed in
  /// (submitted or done) today, [StatsSlice.worked] the timer time.
  final StatsSlice todayStats;

  /// The running timer stretch, if any, and the timer's target task.
  final WorkInterval? running;
  final int? timerTarget;

  int get cutsHandedToday => todayStats.handed;
  Duration get workedToday => todayStats.worked;

  // ---- due soon ----

  /// Cards with work left ([PartGroup.hasWork]) whose production
  /// deadline is within the window or past,
  /// soonest (most late) first.
  final List<DashboardDue> dueSoon;

  // ---- today and tomorrow ----

  /// Events of today and tomorrow — on a card, on an episode, on nothing
  /// (dubbing, meetings, days off) — by day, all-day first, then time.
  final List<EventRow> events;

  /// Public holidays today and tomorrow (the holiday country setting).
  final List<Holiday> holidays;

  // ---- attention ----

  /// Late open cards and cuts ([TodayView.late]).
  int get late => today.late;

  /// Cuts in retake (a shared group once), and the cards holding them.
  final int retakeCuts;
  final List<String> retakeCards;

  /// Open cuts on hold (the store's `holding().waiting`).
  final int waiting;

  // ---- this week ----

  /// This week so far and the whole week before, as statistics ranges
  /// (the week start setting): [StatsSlice.handed], [StatsSlice.worked],
  /// [StatsSlice.earned] per currency.
  final StatsSlice thisWeek;
  final StatsSlice lastWeek;

  /// The first day of this week (local date).
  final DateTime weekFrom;
}
