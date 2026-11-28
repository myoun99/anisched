// The month view: each month a band of the same board.
part of 'chart.dart';

/// The month view: each month a band of its own (1st to last day across
/// the width), the next one under it. A device choice; the main file
/// remembers it.
final chartMonthView = ValueNotifier<bool>(false);

/// The toolbar's switch between the running view and the month view.
class MonthViewToggle extends StatelessWidget {
  const MonthViewToggle({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: chartMonthView,
    builder: (context, month, _) => ToolbarButton(
      key: const Key('chart-month'),
      label: month ? S.viewRunning.t : S.viewMonths.t,
      icon: Icons.calendar_view_month,
      selected: month,
      onTap: () => chartMonthView.value = !month,
    ),
  );
}

/// The window of [month]'s days, 1st to last.
ChartWindow monthWindow(DateTime month) => ChartWindow(
  chartDay(DateTime(month.year, month.month)),
  DateUtils.getDaysInMonth(month.year, month.month),
);

/// The months from [first] to [last] (inclusive), each built by [month]
/// as a shrink-wrapped [ChartBoard] for its window, stacked and scrolled
/// together; only the months on screen are built.
class MonthStack extends StatelessWidget {
  const MonthStack({
    super.key,
    required this.first,
    required this.last,
    required this.month,
  });

  final DateTime first;
  final DateTime last;
  final Widget Function(BuildContext context, ChartWindow window) month;

  @override
  Widget build(BuildContext context) {
    final count = (last.year - first.year) * 12 + last.month - first.month + 1;
    return OwnScroll(
      builder: (controller) => Scrollbar(
        controller: controller,
        child: ListView.builder(
          key: const Key('month-stack'),
          controller: controller,
          itemCount: count < 1 ? 1 : count,
          itemBuilder: (context, i) {
            final m = DateTime(first.year, first.month + i);
            return Padding(
              key: Key('month-${m.year}-${m.month}'),
              padding: const EdgeInsets.only(bottom: 14),
              child: month(context, monthWindow(m)),
            );
          },
        ),
      ),
    );
  }
}
