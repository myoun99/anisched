import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../models/progress.dart';
import '../../services/catalogue_reader.dart';
import '../../services/catalogue_store.dart';
import '../../services/document_session.dart';
import '../../services/device_settings.dart';
import '../../services/recovery_snapshots.dart';
import '../document_menu.dart';
import '../format.dart';
import '../instant.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text/strings.dart';

/// The user's settings: rest weekdays, days off, parallel lanes, when a
/// day starts, per-second rounding, usual speeds and this month's pay.
/// Segmented rows share their width evenly.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.now,
    this.store,
    this.reader,
    this.paces = const {},
    this.refresh = 0,
    this.onChanged,
    this.session,
    this.remote,
  });

  /// The last resume check, for the save state.
  final ValueListenable<RemoteCheck?>? remote;

  /// The document session, for its recovery snapshots; null hides them.
  final DocumentSession? session;

  final DateTime now;

  /// Reads and writes the settings; null shows defaults, read-only.
  final CatalogueStore? store;

  /// For this month's totals.
  final CatalogueReader? reader;

  /// Usual speeds by stage name.
  final Map<String, StagePace> paces;

  /// Bumped by the shell after writes elsewhere; reloads the totals.
  final int refresh;

  /// Called after a setting is written, so the views reload.
  final VoidCallback? onChanged;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

final _noRemote = ValueNotifier<RemoteCheck?>(null);

class _SettingsViewState extends State<SettingsView> {
  MonthlyTotals _totals = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadTotals());
  }

  @override
  void didUpdateWidget(SettingsView old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) unawaited(_loadTotals());
  }

  Future<void> _loadTotals() async {
    final r = widget.reader;
    if (r == null) return;
    final t = await r.monthlyTotals(widget.now.year, widget.now.month);
    if (mounted) setState(() => _totals = t);
  }

  void _set(void Function(CatalogueStore s) write) {
    final s = widget.store;
    if (s == null) return;
    write(s);
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _addDaysOff() async {
    final r = await showInstantDateRangePicker(
      context: context,
      firstDate: DateTime(widget.now.year - 1),
      lastDate: DateTime(widget.now.year + 2),
      title: S.daysOff.t,
    );
    if (r == null || !mounted) return;
    _set((s) => s.addDaysOff(r.start, end: r.end));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = widget.store?.settings;
    final rest = s?.restWeekdays ?? {DateTime.saturday, DateTime.sunday};
    final dayStart = s?.dayStartMinutes ?? 0;
    final rounding = s?.secondsRounding ?? SecondsRounding.nearest;
    final off = widget.store?.daysOff() ?? const [];
    final weekdays = weekdayNames();
    final display = _Group(
      icon: Icons.palette_outlined,
      title: S.display.t,
      children: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeSetting,
          builder: (context, mode, _) => _FillRow(
            children: [
              for (final (m, icon, l) in [
                (
                  ThemeMode.system,
                  Icons.brightness_auto_outlined,
                  S.themeSystem.t,
                ),
                (ThemeMode.light, Icons.light_mode_outlined, S.themeLight.t),
                (ThemeMode.dark, Icons.dark_mode_outlined, S.themeDark.t),
              ])
                SegmentButton(
                  key: Key('theme-${m.name}'),
                  icon: icon,
                  label: l,
                  selected: mode == m,
                  onTap: () => themeModeSetting.value = m,
                ),
            ],
          ),
        ),
        ValueListenableBuilder<LanguageChoice>(
          valueListenable: languageSetting,
          builder: (context, choice, _) => _Field(
            icon: Icons.translate,
            label: S.language.t,
            child: _FillRow(
              children: [
                for (final l in LanguageChoice.values)
                  SegmentButton(
                    key: Key('lang-${l.name}'),
                    compact: true,
                    icon: l == LanguageChoice.device
                        ? Icons.smartphone_outlined
                        : null,
                    tooltip: l == LanguageChoice.device ? S.langDevice.t : null,
                    label: _langLabel(l),
                    selected: choice == l,
                    onTap: () => languageSetting.value = l,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    final restDays = _Group(
      icon: Icons.event_busy_outlined,
      title: S.daysOff.t,
      children: [
        _Field(
          icon: Icons.repeat,
          label: S.restWeekdays.t,
          child: _FillRow(
            children: [
              for (var d = 1; d <= 7; d++)
                SegmentButton(
                  key: Key('rest-$d'),
                  compact: true,
                  label: weekdays[d - 1],
                  selected: rest.contains(d),
                  onTap: () => _set(
                    (st) => st.settings.restWeekdays = rest.contains(d)
                        ? (rest.toSet()..remove(d))
                        : (rest.toSet()..add(d)),
                  ),
                ),
            ],
          ),
        ),
        for (final o in off)
          _Line(
            children: [
              Text(
                o.range.start == o.range.end
                    ? formatDate(o.range.start)
                    : '${formatDate(o.range.start)} – ${formatDate(o.range.end)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (o.note != null)
                Expanded(
                  child: Text(
                    o.note!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted),
                  ),
                )
              else
                const Spacer(),
              _IconAction(
                icon: Icons.delete_outline,
                tooltip: S.remove.t,
                onTap: () => _set((st) => st.removeDaysOff(o.id)),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('days-off-add'),
            onPressed: widget.store == null ? null : _addDaysOff,
            icon: const Icon(Icons.add, size: 18),
            label: Text(S.add.t),
          ),
        ),
      ],
    );
    final workLines = _Group(
      icon: Icons.view_timeline_outlined,
      title: S.viewWork.t,
      children: [
        // Lanes are added and named in the work tab's header now.
        _Field(
          icon: Icons.wb_twilight_outlined,
          label: S.dayStart.t,
          child: _FillRow(
            children: [
              for (final m in const [0, 240, 360])
                SegmentButton(
                  label: '${m ~/ 60}:00',
                  selected: dayStart == m,
                  onTap: () => _set((st) => st.settings.dayStartMinutes = m),
                ),
            ],
          ),
        ),
        _Line(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: c.muted),
            Expanded(child: Text(S.timerAuto.t)),
            Switch(
              key: const Key('timer-auto-start'),
              value: widget.store?.settings.timerAutoStart ?? false,
              onChanged: widget.store == null
                  ? null
                  : (v) => _set((st) => st.settings.timerAutoStart = v),
            ),
          ],
        ),
        if (widget.paces.isNotEmpty)
          _Field(
            icon: Icons.speed_outlined,
            label: S.usualPace.t,
            child: Column(
              spacing: 6,
              children: [
                for (final p in widget.paces.values)
                  _Line(
                    children: [
                      Expanded(
                        child: Text(
                          p.stageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: '${_one(p.overall.perDay)} · ${S.recent.t} ',
                          style: TextStyle(color: c.muted),
                          children: [
                            TextSpan(
                              text: _one(p.recent.perDay),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: DefaultTextStyle.of(context).style.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
    final pay = _Group(
      icon: Icons.payments_outlined,
      title: S.rate.t,
      children: [
        _Field(
          icon: Icons.exposure_outlined,
          label: S.rounding.t,
          child: _FillRow(
            children: [
              for (final (r, l) in [
                (SecondsRounding.nearest, S.rNearest.t),
                (SecondsRounding.up, S.rUp.t),
                (SecondsRounding.down, S.rDown.t),
                (SecondsRounding.exact, S.rExact.t),
              ])
                SegmentButton(
                  label: l,
                  selected: rounding == r,
                  onTap: () => _set((st) => st.settings.secondsRounding = r),
                ),
            ],
          ),
        ),
        _Field(
          icon: Icons.task_alt,
          label: S.monthDone.t,
          child: Column(
            spacing: 6,
            children: [
              for (final e in _totals.entries)
                _Line(
                  children: [
                    Text(
                      formatMoney(e.key, e.value.total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (e.value.unpriced > 0)
                      Flexible(
                        child: Text(
                          S.unpriced.f({'n': e.value.unpriced}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted),
                        ),
                      ),
                  ],
                ),
              if (_totals.isEmpty)
                _Line(
                  children: [Text('—', style: TextStyle(color: c.muted))],
                ),
            ],
          ),
        ),
      ],
    );
    final doc = widget.session;
    final storage = doc == null
        ? null
        : _Group(
            icon: Icons.save_outlined,
            title: S.storage.t,
            children: [
              ValueListenableBuilder<RemoteCheck?>(
                valueListenable: widget.remote ?? _noRemote,
                builder: (context, remote, _) {
                  final st = SaveState.of(context, doc, remote);
                  return _Line(
                    children: [
                      Icon(
                        st.icon,
                        key: const Key('settings-save-state'),
                        size: 18,
                        color: st.color,
                      ),
                      Text(
                        st.word,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Expanded(
                        child: Text(
                          st.detail ?? DocumentMenu.displayName(doc.document),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted),
                        ),
                      ),
                    ],
                  );
                },
              ),
              for (final snap in doc.snapshots.list().take(20))
                _Line(
                  children: [
                    Icon(
                      snap.reason == SnapshotReason.overwritten
                          ? Icons.file_copy_outlined
                          : Icons.history,
                      size: 18,
                      color: c.muted,
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text:
                              '${formatDate(snap.takenAt)} '
                              '${snap.takenAt.toLocal().hour}:'
                              '${snap.takenAt.toLocal().minute.toString().padLeft(2, '0')}  ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          children: [
                            TextSpan(
                              text: snap.reason == SnapshotReason.overwritten
                                  ? S.overwritten.t
                                  : S.beforeChange.t,
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _IconAction(
                      icon: Icons.restore,
                      tooltip: S.revive.t,
                      onTap: () => unawaited(doc.restoreSnapshot(snap.path)),
                    ),
                  ],
                ),
            ],
          );
    final groups = [display, restDays, workLines, pay, ?storage];
    return ColoredBox(
      color: c.panel,
      child: OwnScroll(
        builder: (controller) => Scrollbar(
          controller: controller,
          child: LayoutBuilder(
            builder: (context, box) {
              const gap = 16.0;
              final two = box.maxWidth >= 1000;
              final colWidth = two
                  ? ((box.maxWidth - 36 - gap) / 2).clamp(0.0, 540.0)
                  : (box.maxWidth - 36).clamp(0.0, 560.0);
              Widget column(List<Widget> gs) => SizedBox(
                width: colWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: gs,
                ),
              );
              return SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: two
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          spacing: gap,
                          children: [
                            column([display, restDays, workLines]),
                            column([pay, ?storage]),
                          ],
                        )
                      : column(groups),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _langLabel(LanguageChoice l) => switch (l) {
    LanguageChoice.device => '',
    LanguageChoice.en => 'EN',
    LanguageChoice.ja => '日本',
    LanguageChoice.ko => '한국',
    LanguageChoice.fr => 'FR',
    LanguageChoice.zhHans => '中文',
  };

  static String _one(double? v) => v == null
      ? '—'
      : (v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1));
}

/// A settings card: an icon and a title, then its rows.
class _Group extends StatelessWidget {
  const _Group({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(icon, size: 20, color: accent),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

/// A small icon and label above a control.
class _Field extends StatelessWidget {
  const _Field({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 5,
      children: [
        Row(
          spacing: 6,
          children: [
            Icon(icon, size: 15, color: c.muted),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ],
        ),
        child,
      ],
    );
  }
}

/// An icon button with a tooltip, sized for a [_Line].
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
  );
}

/// Segment buttons sharing the row's width evenly.
class _FillRow extends StatelessWidget {
  const _FillRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, color: c.line),
                Expanded(child: children[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One boxed line in a section.
class _Line extends StatelessWidget {
  const _Line({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(spacing: 12, children: children),
      ),
    );
  }
}
