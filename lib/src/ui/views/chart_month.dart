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
/// as a shrink-wrapped [ChartBoard] for its window, stacked edge to edge
/// with one line between them and scrolled together; only the months on
/// screen are built.
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
    final line = AppColors.of(context).line;
    return OwnScroll(
      builder: (controller) => Scrollbar(
        controller: controller,
        child: ListView.builder(
          key: const Key('month-stack'),
          controller: controller,
          itemCount: count < 1 ? 1 : count,
          itemBuilder: (context, i) {
            final m = DateTime(first.year, first.month + i);
            // No gap between months: one line where one ends.
            return DecoratedBox(
              key: Key('month-${m.year}-${m.month}'),
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: line)),
              ),
              child: month(context, monthWindow(m)),
            );
          },
        ),
      ),
    );
  }
}

/// A month band's ruler rows: [base]'s weekdays, no year or month row —
/// the band's corner names its month ([MonthCorner]).
class MonthRuler implements ValueListenable<RulerRows> {
  const MonthRuler(this.base);

  final ValueListenable<RulerRows> base;

  @override
  RulerRows get value =>
      (year: false, month: false, weekday: base.value.weekday);

  @override
  void addListener(VoidCallback listener) => base.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => base.removeListener(listener);
}

/// A month band's corner, over its row names: 「2026 11月」 (the year when
/// the tab's ruler shows years), in place of a month header of its own.
class MonthCorner extends StatelessWidget {
  const MonthCorner({super.key, required this.month, required this.rows});

  final DateTime month;
  final ValueListenable<RulerRows> rows;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RulerRows>(
    valueListenable: rows,
    builder: (context, r, _) => Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FitText(
          [if (r.year) '${month.year}', monthName(month.month)].join(' '),
          key: Key('month-corner-${month.year}-${month.month}'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

/// The toolbar's ruler settings for [tab]: a small menu of the year,
/// month and weekday rows, each a switch; kept per tab on this device.
class RulerRowsButton extends StatelessWidget {
  const RulerRowsButton({super.key, required this.tab});

  final RulerTab tab;

  @override
  Widget build(BuildContext context) {
    final rows = rulerRows[tab]!;
    return ValueListenableBuilder<RulerRows>(
      valueListenable: rows,
      builder: (context, r, _) {
        Widget line(RulerRow row, IconData icon, String label, bool on) =>
            MenuItemButton(
              key: Key('ruler-row-${row.name}'),
              closeOnActivate: false,
              leadingIcon: Icon(icon, size: 18),
              trailingIcon: Switch(
                value: on,
                onChanged: (v) => rows.value = _with(r, row, v),
              ),
              onPressed: () => rows.value = _with(r, row, !on),
              child: Text(label),
            );
        return MenuAnchor(
          menuChildren: [
            line(
              RulerRow.year,
              Icons.event_note_outlined,
              S.rulerYear.t,
              r.year,
            ),
            line(
              RulerRow.month,
              Icons.calendar_month_outlined,
              S.rulerMonth.t,
              r.month,
            ),
            line(
              RulerRow.weekday,
              Icons.view_week_outlined,
              S.rulerWeekday.t,
              r.weekday,
            ),
          ],
          builder: (context, menu, _) => ToolbarButton(
            key: const Key('ruler-rows'),
            label: S.rulerRows.t,
            icon: Icons.tune,
            selected: menu.isOpen,
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        );
      },
    );
  }

  static RulerRows _with(RulerRows r, RulerRow row, bool on) => (
    year: row == RulerRow.year ? on : r.year,
    month: row == RulerRow.month ? on : r.month,
    weekday: row == RulerRow.weekday ? on : r.weekday,
  );
}
