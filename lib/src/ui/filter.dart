import 'package:flutter/material.dart';

import 'instant.dart';

import '../models/catalogue.dart';
import '../models/progress.dart';
import 'widgets.dart';

/// The deadline windows the filter offers. Except [all], handed-in work
/// (submitted or done) never matches.
enum DueRange {
  all('전체'),
  today('오늘'),
  late('지난 것'),
  within3('3일 안'),
  within14('2주 안'),
  later('그 뒤');

  const DueRange(this.label);

  final String label;
}

/// What the list and the timeline show: one deadline window, one client,
/// one work, and whether done work is listed.
class ViewFilter {
  const ViewFilter({
    this.range = DueRange.all,
    this.clientId,
    this.workId,
    this.showDone = false,
  });

  final DueRange range;
  final int? clientId;
  final int? workId;
  final bool showDone;

  bool get isDefault =>
      range == DueRange.all && clientId == null && workId == null && !showDone;

  ViewFilter copyWith({
    DueRange? range,
    int? Function()? clientId,
    int? Function()? workId,
    bool? showDone,
  }) => ViewFilter(
    range: range ?? this.range,
    clientId: clientId == null ? this.clientId : clientId(),
    workId: workId == null ? this.workId : workId(),
    showDone: showDone ?? this.showDone,
  );

  /// Whether [g] passes, as of [now]. [clientOf] maps work ids to their
  /// client ids.
  bool matches(
    PartGroup g,
    DateTime now,
    Map<int, int?> clientOf, {
    int dayStartMinutes = 0,
  }) {
    if (!showDone && g.status == TaskStatus.done) return false;
    if (workId != null && g.workId != workId) return false;
    if (clientId != null && clientOf[g.workId] != clientId) return false;
    if (range == DueRange.all) return true;
    if (!g.status.isOpen || g.status == TaskStatus.submitted) return false;
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
  final Map<int, String> clients;

  /// Work titles by id.
  final Map<int, String> works;

  String get _label {
    final parts = [
      if (filter.range != DueRange.all) filter.range.label,
      if (filter.clientId != null) clients[filter.clientId] ?? '',
      if (filter.workId != null) works[filter.workId] ?? '',
      if (filter.showDone) '완료 포함',
    ];
    return parts.isEmpty ? '전체' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<_Choice> item(_Choice v, String text, bool on) =>
        CheckedPopupMenuItem<_Choice>(value: v, checked: on, child: Text(text));
    PopupMenuItem<_Choice> head(String text) => PopupMenuItem<_Choice>(
      enabled: false,
      height: 28,
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
    return PopupMenuButton<_Choice>(
      key: const Key('filter-button'),
      tooltip: '',
      popUpAnimationStyle: instant,
      onSelected: (c) => onChanged(switch (c) {
        _Range(:final range) => filter.copyWith(range: range),
        _Client(:final id) => filter.copyWith(clientId: () => id),
        _Work(:final id) => filter.copyWith(workId: () => id),
        _Done() => filter.copyWith(showDone: !filter.showDone),
      }),
      itemBuilder: (_) => [
        head('기간'),
        for (final r in DueRange.values)
          item(_Range(r), r.label, filter.range == r),
        if (clients.isNotEmpty) ...[
          head('회사'),
          item(const _Client(null), '모든 회사', filter.clientId == null),
          for (final e in clients.entries)
            item(_Client(e.key), e.value, filter.clientId == e.key),
        ],
        head('작품'),
        item(const _Work(null), '모든 작품', filter.workId == null),
        for (final e in works.entries)
          item(_Work(e.key), e.value, filter.workId == e.key),
        head('완료'),
        item(const _Done(), '완료도 보기', filter.showDone),
      ],
      child: ToolbarButton(
        label: _label,
        selected: !filter.isDefault,
        dropdown: true,
      ),
    );
  }
}
