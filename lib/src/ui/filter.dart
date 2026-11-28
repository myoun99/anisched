import 'package:flutter/material.dart';

import 'client_chip.dart';
import 'instant.dart';

import '../models/progress.dart';
import 'theme.dart';
import 'widgets.dart';
import 'text/strings.dart';

/// The deadline windows the filter offers. Except [all], handed-in work
/// (submitted or done) never matches.
enum DueRange {
  all(S.fAll),
  today(S.today),
  late(S.fLate),
  within3(S.fWithin3),
  within14(S.fWithin14),
  later(S.fLater);

  const DueRange(this.word);

  final S word;

  String get label => word.t;
}

/// What the list and the timeline show: one deadline window, one client,
/// one work, and whether done work is listed.
class ViewFilter {
  const ViewFilter({
    this.range = DueRange.all,
    this.clientId,
    this.workId,
    this.showDone = false,
    this.showHandedOff = false,
    this.showArchived = false,
  });

  final DueRange range;
  final int? clientId;
  final int? workId;
  final bool showDone;

  /// Also list work pulled from the user (引き上げ).
  final bool showHandedOff;

  /// Also list work put away (보관), faded.
  final bool showArchived;

  bool get isDefault =>
      range == DueRange.all &&
      clientId == null &&
      workId == null &&
      !showDone &&
      !showHandedOff &&
      !showArchived;

  ViewFilter copyWith({
    DueRange? range,
    int? Function()? clientId,
    int? Function()? workId,
    bool? showDone,
    bool? showHandedOff,
    bool? showArchived,
  }) => ViewFilter(
    range: range ?? this.range,
    clientId: clientId == null ? this.clientId : clientId(),
    workId: workId == null ? this.workId : workId(),
    showDone: showDone ?? this.showDone,
    showHandedOff: showHandedOff ?? this.showHandedOff,
    showArchived: showArchived ?? this.showArchived,
  );

  /// Whether [g] passes, as of [now]. [clientOf] maps work ids to their
  /// client ids.
  bool matches(
    PartGroup g,
    DateTime now,
    Map<int, int?> clientOf, {
    int dayStartMinutes = 0,
  }) {
    // Handed in (submitted) work leaves the list unless asked for.
    // Put away work, when shown, shows whatever its state.
    if (!showDone && g.status.isHanded && !g.archived) return false;
    if (workId != null && g.workId != workId) return false;
    if (clientId != null && clientOf[g.workId] != clientId) return false;
    if (range == DueRange.all) return true;
    if (!g.status.isOpen) return false; // handed in: submitted or done
    if (range == DueRange.today) {
      final start = g.planStartAt ?? g.kickoffAt;
      return start != null && !start.isAfter(now);
    }
    final due = g.dueAt;
    if (due == null) return false;
    final d = dueInDays(due, now, dayStartMinutes);
    return switch (range) {
      DueRange.late => d < 0,
      DueRange.within3 => d >= 0 && d <= 3,
      DueRange.within14 => d > 3 && d <= 14,
      DueRange.later => d > 14,
      DueRange.all || DueRange.today => true,
    };
  }
}

sealed class _Choice {
  const _Choice();
}

class _Range extends _Choice {
  const _Range(this.range);
  final DueRange range;
}

class _Client extends _Choice {
  const _Client(this.id);
  final int? id;
}

class _Work extends _Choice {
  const _Work(this.id);
  final int? id;
}

class _Done extends _Choice {
  const _Done();
}

class _Archived extends _Choice {
  const _Archived();
}

class _HandedOff extends _Choice {
  const _HandedOff();
}

/// One button for every filter: its face names what is chosen
/// (「전체」 when nothing is), the menu lists 기간 · 회사 · 작품 · 완료.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.filter,
    required this.onChanged,
    this.clients = const {},
    this.works = const {},
  });

  final ViewFilter filter;
  final ValueChanged<ViewFilter> onChanged;

  /// Client names by id.
  final Map<int, ClientTag> clients;

  /// Work titles by id.
  final Map<int, String> works;

  String get _label {
    final parts = [
      if (filter.range != DueRange.all) filter.range.label,
      if (filter.clientId != null) clients[filter.clientId]?.name ?? '',
      if (filter.workId != null) works[filter.workId] ?? '',
      if (filter.showDone) S.fWithDone.t,
      if (filter.showHandedOff) S.dropped.t,
      if (filter.showArchived) S.archive.t,
    ];
    return parts.isEmpty ? S.fAll.t : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // Compact rows: a small check, the label; section names as dim
    // captions. No Material check-row padding.
    final c = AppColors.of(context);
    PopupMenuItem<_Choice> item(
      _Choice v,
      String text,
      bool on, {
      ClientTag? client,
      IconData? icon,
    }) => PopupMenuItem<_Choice>(
      key: icon == null ? null : const Key('filter-archived'),
      value: v,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        spacing: 6,
        children: [
          SizedBox(
            width: 14,
            child: on ? const Icon(Icons.check, size: 14) : null,
          ),
          if (icon != null) Icon(icon, size: 14, color: c.muted),
          Flexible(
            child: client != null
                ? ClientChip(client, fitName: false)
                : Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w700 : null,
                    ),
                  ),
          ),
        ],
      ),
    );
    PopupMenuItem<_Choice> head(String text) => PopupMenuItem<_Choice>(
      enabled: false,
      height: 22,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Text(text, style: TextStyle(fontSize: 11, color: c.muted)),
    );
    return PopupMenuButton<_Choice>(
      key: const Key('filter-button'),
      tooltip: '',
      popUpAnimationStyle: instant,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      onSelected: (c) => onChanged(switch (c) {
        _Range(:final range) => filter.copyWith(range: range),
        _Client(:final id) => filter.copyWith(clientId: () => id),
        _Work(:final id) => filter.copyWith(workId: () => id),
        _Done() => filter.copyWith(showDone: !filter.showDone),
        _HandedOff() => filter.copyWith(showHandedOff: !filter.showHandedOff),
        _Archived() => filter.copyWith(showArchived: !filter.showArchived),
      }),
      itemBuilder: (_) => [
        head(S.fPeriod.t),
        for (final r in DueRange.values)
          item(_Range(r), r.label, filter.range == r),
        if (clients.isNotEmpty) ...[
          head(S.client.t),
          item(const _Client(null), S.allClients.t, filter.clientId == null),
          for (final e in clients.entries)
            item(
              _Client(e.key),
              e.value.name,
              filter.clientId == e.key,
              client: e.value,
            ),
        ],
        head(S.title.t),
        item(const _Work(null), S.allTitles.t, filter.workId == null),
        for (final e in works.entries)
          item(_Work(e.key), e.value, filter.workId == e.key),
        head(S.stSubmitted.t),
        item(const _Done(), S.showDone.t, filter.showDone),
        item(const _HandedOff(), S.showDropped.t, filter.showHandedOff),
        item(
          const _Archived(),
          S.showArchived.t,
          filter.showArchived,
          icon: Icons.archive_outlined,
        ),
      ],
      child: ToolbarButton(
        label: _label,
        icon: Icons.filter_list,
        selected: !filter.isDefault,
        dropdown: true,
      ),
    );
  }
}
