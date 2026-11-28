import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/size_class.dart';
import '../../models/dashboard.dart';
import '../../models/progress.dart';
import '../../services/catalogue_reader.dart';
import '../catalogue_browser.dart';
import '../client_chip.dart';
import '../fit_text.dart';
import '../format.dart';
import '../palette.dart';
import '../part_line.dart';
import '../text/strings.dart';
import '../theme.dart';
import '../widgets.dart';

/// The dashboard (유저 2026-11-28): today in three numbers, cards due
/// soon, today's and tomorrow's schedule, what needs attention, and this
/// week against the last — a few cards, a group hidden when empty. Read
/// in one go ([CatalogueReader.dashboard]) whenever the tab shows or the
/// document changes.
class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.now,
    required this.layout,
    this.reader,
    this.visible = true,
    this.refresh = 0,
    this.clientOf,
    this.onOpen,
  });

  final DateTime now;
  final ScreenLayout layout;
  final CatalogueReader? reader;

  /// Reads only while shown (the tab keeps its state when hidden).
  final bool visible;

  /// Bumped by the shell after every write: read again.
  final int refresh;

  final ClientTag? Function(PartGroup g)? clientOf;

  /// A due card tapped: the list opens it.
  final ValueChanged<PartGroup>? onOpen;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  Dashboard? _d;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    if (widget.visible) unawaited(_load());
  }

  @override
  void didUpdateWidget(DashboardView old) {
    super.didUpdateWidget(old);
    if (widget.visible &&
        (!old.visible ||
            old.refresh != widget.refresh ||
            old.reader != widget.reader)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final reader = widget.reader;
    if (reader == null) return;
    final ask = ++_asked;
    final d = await reader.dashboard();
    if (mounted && ask == _asked) setState(() => _d = d);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = _d;
    if (d == null) {
      // Hidden, or nothing to read: nothing spins.
      if (!widget.visible || widget.reader == null) {
        return ColoredBox(color: c.panel);
      }
      return ColoredBox(
        color: c.panel,
        child: const Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              key: Key('dash-loading'),
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    final cards = <Widget>[
      if (d.dueSoon.isNotEmpty) _dueSoon(context, d),
      if (d.events.isNotEmpty || d.holidays.isNotEmpty) _agenda(context, d),
      if (d.late > 0 || d.retakeCuts > 0 || d.waiting > 0)
        _attention(context, d),
      _week(context, d),
    ];
    return ColoredBox(
      color: c.panel,
      child: LayoutBuilder(
        builder: (context, box) {
          // Two columns on a wide screen: due soon on the left.
          final two = box.maxWidth >= 900 && cards.length > 1;
          return ListView(
            key: const Key('dashboard'),
            padding: const EdgeInsets.all(12),
            children: [
              _tiles(context, d),
              const SizedBox(height: 10),
              if (two)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 10,
                  children: [
                    Expanded(child: cards.first),
                    Expanded(
                      child: Column(
                        spacing: 10,
                        children: cards.skip(1).toList(),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: cards,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Today's three numbers: cuts today asks, cuts handed in, timer time.
  Widget _tiles(BuildContext context, Dashboard d) {
    final n = d.today.cutsToday;
    final ask = n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);
    return Row(
      spacing: 10,
      children: [
        for (final (key, icon, value, label) in [
          ('dash-ask', Icons.flag_outlined, ask, S.dashAsk.t),
          (
            'dash-handed',
            Icons.check_circle_outline,
            '${d.cutsHandedToday}',
            S.dashHanded.t,
          ),
          (
            'dash-worked',
            Icons.timer_outlined,
            formatWorked(d.workedToday),
            S.dashWorked.t,
          ),
        ])
          Expanded(
            child: Panel(
              key: Key(key),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: _tile(context, icon, value, label),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String value, String l) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Row(
          spacing: 4,
          children: [
            Icon(icon, size: 14, color: c.muted),
            Flexible(
              child: FitText(l, style: TextStyle(fontSize: 12, color: c.muted)),
            ),
          ],
        ),
        FitText(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// A card of the dashboard: an icon and title, then its lines.
  Widget _card(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final c = AppColors.of(context);
    return Panel(
      key: Key(key),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            spacing: 6,
            children: [
              Icon(icon, size: 16, color: c.muted),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _dueSoon(BuildContext context, Dashboard d) {
    final red = Theme.of(context).colorScheme.error;
    return _card(
      context,
      key: 'dash-due',
      icon: Icons.schedule,
      title: S.dashDue.t,
      children: [for (final due in d.dueSoon) _dueLine(context, due, red)],
    );
  }

  /// One card due soon: its name, then cuts left, per day and D-n — on
  /// one line, or two on an upright phone (the name above, 유저
  /// 2026-11-28). A tap opens the card on the list.
  Widget _dueLine(BuildContext context, DashboardDue due, Color red) {
    final c = AppColors.of(context);
    final g = due.group;
    final k = g.key;
    final name = Row(
      key: Key('dash-due-name-$k'),
      spacing: 8,
      children: [
        if (widget.clientOf?.call(g) case final tag?)
          ClientChip(tag, compact: true),
        Dot(stageColor(g.stageName)),
        Expanded(
          child: FitText('${g.workTitle} ${g.episodeNumber} · ${unitTitle(g)}'),
        ),
      ],
    );
    final figures = [
      Text('${due.remaining} cut', style: TextStyle(color: c.muted)),
      SizedBox(
        width: 64,
        child: FitText(
          perDayText(due.pace),
          textAlign: TextAlign.right,
          style: TextStyle(color: c.muted),
        ),
      ),
      SizedBox(
        key: Key('dash-due-days-$k'),
        width: 64,
        child: FitText(
          due.daysLeft < 0
              ? S.daysLate.f({'n': -due.daysLeft})
              : (due.daysLeft == 0 ? 'D-day' : 'D-${due.daysLeft}'),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: due.late ? red : null,
          ),
        ),
      ),
    ];
    final two = widget.layout.size == SizeClass.narrow;
    return InkWell(
      key: Key('dash-due-$k'),
      onTap: widget.onOpen == null ? null : () => widget.onOpen!(g),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: two
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 2,
                children: [
                  name,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: figures,
                  ),
                ],
              )
            : Row(
                spacing: 8,
                children: [
                  Expanded(child: name),
                  ...figures,
                ],
              ),
      ),
    );
  }

  /// Today's and tomorrow's events and holidays, by day, all-day first.
  Widget _agenda(BuildContext context, Dashboard d) {
    final c = AppColors.of(context);
    final day = DateTime(d.day.year, d.day.month, d.day.day);
    String when(DateTime t) =>
        DateTime(t.year, t.month, t.day) == day ? S.today.t : S.tomorrow.t;
    final lines =
        <(DateTime, int, Widget)>[
          for (final h in d.holidays)
            (
              h.date,
              -1,
              _agendaLine(context, when(h.date), '', h.name, c.restDay),
            ),
          for (final e in d.events)
            (
              e.date,
              e.timeMinutes ?? -1,
              _agendaLine(
                context,
                when(e.date),
                e.timeMinutes == null
                    ? ''
                    : '${e.timeMinutes! ~/ 60}:${(e.timeMinutes! % 60).toString().padLeft(2, '0')}',
                [e.title, ?e.card].join(' · '),
                e.rest ? c.restDay : null,
              ),
            ),
        ]..sort((a, b) {
          final k = DateTime(
            a.$1.year,
            a.$1.month,
            a.$1.day,
          ).compareTo(DateTime(b.$1.year, b.$1.month, b.$1.day));
          return k != 0 ? k : a.$2.compareTo(b.$2);
        });
    return _card(
      context,
      key: 'dash-agenda',
      icon: Icons.event_outlined,
      title: S.dashAgenda.t,
      children: [for (final l in lines) l.$3],
    );
  }

  Widget _agendaLine(
    BuildContext context,
    String day,
    String time,
    String title,
    Color? color,
  ) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 30,
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 40,
            child: FitText(day, style: TextStyle(fontSize: 12, color: c.muted)),
          ),
          SizedBox(
            width: 40,
            child: Text(
              time,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: FitText(title, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }

  /// Late, retakes, on hold: each a count, shown when there are any.
  Widget _attention(BuildContext context, Dashboard d) {
    final c = AppColors.of(context);
    final red = Theme.of(context).colorScheme.error;
    return _card(
      context,
      key: 'dash-attention',
      icon: Icons.warning_amber_rounded,
      title: S.dashAttention.t,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            if (d.late > 0)
              _count(
                'dash-late',
                Icons.error_outline,
                S.lateN.f({'n': d.late}),
                red,
              ),
            if (d.retakeCuts > 0)
              _count(
                'dash-retake',
                Icons.replay,
                '${S.stRetake.t} ${d.retakeCuts}',
                c.retake,
              ),
            if (d.waiting > 0)
              _count(
                'dash-waiting',
                Icons.pause_circle_outline,
                '${S.hold.t} ${d.waiting}',
                c.muted,
              ),
          ],
        ),
      ],
    );
  }

  Widget _count(String key, IconData icon, String text, Color color) => Row(
    key: Key(key),
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      Icon(icon, size: 16, color: color),
      Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    ],
  );

  /// This week so far against the whole week before: cuts handed in and
  /// timer time, each with an arrow.
  Widget _week(BuildContext context, Dashboard d) {
    final c = AppColors.of(context);
    Widget line(
      String key,
      String label,
      String now,
      String before,
      int diff,
    ) => SizedBox(
      key: Key(key),
      height: 30,
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: FitText(label, style: TextStyle(color: c.muted)),
          ),
          Text(
            now,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Icon(
            diff > 0
                ? Icons.arrow_upward
                : (diff < 0 ? Icons.arrow_downward : Icons.remove),
            size: 14,
            color: diff > 0 ? c.good : (diff < 0 ? c.retake : c.faint),
          ),
          SizedBox(
            width: 64,
            child: FitText(
              before,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        ],
      ),
    );
    final a = d.thisWeek;
    final b = d.lastWeek;
    return _card(
      context,
      key: 'dash-week',
      icon: Icons.date_range_outlined,
      title: S.dashWeek.t,
      children: [
        line(
          'dash-week-cuts',
          S.dashHandedWeek.t,
          '${a.handed} cut',
          '${b.handed} cut',
          a.handed.compareTo(b.handed),
        ),
        line(
          'dash-week-worked',
          S.kWorked.t,
          formatWorked(a.worked),
          formatWorked(b.worked),
          a.worked.compareTo(b.worked),
        ),
      ],
    );
  }
}
