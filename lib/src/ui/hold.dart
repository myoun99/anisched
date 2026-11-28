/// On-hold (대기) and deadline-round (차수) pieces shared by the views.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/progress.dart';
import 'due_button.dart';
import 'format.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// What the hold dialog answers: a short reason and an expected day, both
/// optional.
typedef HoldNote = ({String? reason, DateTime? until});

/// Asks for a hold's reason and expected day; null when cancelled.
Future<HoldNote?> askHold(BuildContext context) => showInstantDialog<HoldNote>(
  context: context,
  builder: (_) => _HoldDialog(),
);

class _HoldDialog extends StatefulWidget {
  @override
  State<_HoldDialog> createState() => _HoldDialogState();
}

class _HoldDialogState extends State<_HoldDialog> {
  final _reason = TextEditingController();
  DateTime? _until;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop<HoldNote>((
    reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
    until: _until,
  ));

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: Row(
        spacing: 8,
        children: [const Icon(Icons.pause_circle_outline), Text(S.hold.t)],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          TextField(
            key: const Key('hold-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(labelText: S.holdReason.t),
            onSubmitted: (_) => _done(),
          ),
          DueButton(
            key: const Key('hold-until'),
            title: S.pickHoldUntil.t,
            due: _until,
            onPicked: (d) => setState(() => _until = d),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.event_outlined, size: 18, color: c.muted),
                  Text(S.holdExpected.t, style: TextStyle(color: c.muted)),
                  Text(
                    _until == null ? '—' : formatDate(_until),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel.t),
        ),
        FilledButton(
          key: const Key('hold-ok'),
          onPressed: _done,
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}

/// 「2차」 / 「Round 2」 / 「1re échéance」.
String dueRoundLabel(int n) => appLang.value == Lang.fr && n == 1
    ? '1re échéance'
    : S.dueRound.f({'n': n});

/// The small number beside a deadline that has been extended: 「2」 for
/// the 2nd deadline. Nothing for the first.
class RoundBadge extends StatelessWidget {
  const RoundBadge(this.revision, {super.key});

  final int revision;

  @override
  Widget build(BuildContext context) {
    if (revision < 2) return const SizedBox.shrink();
    final c = AppColors.of(context);
    return Tooltip(
      message: dueRoundLabel(revision),
      child: Padding(
        padding: const EdgeInsets.only(left: 3, bottom: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.muted, width: 0.8),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Text(
              '$revision',
              style: TextStyle(
                fontSize: 9,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small ⏸ mark of something on hold, with an optional count.
class HoldMark extends StatelessWidget {
  const HoldMark({super.key, this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 1,
      children: [
        Icon(Icons.pause_circle_outline, size: 12, color: c.submitted),
        if (count != null)
          Text('$count', style: TextStyle(fontSize: 11, color: c.submitted)),
      ],
    );
  }
}

/// The deadline's rounds, each one tappable to correct its date. Loads
/// when shown and again when the deadline changes.
class DueRevisionList extends StatefulWidget {
  const DueRevisionList({
    super.key,
    required this.load,
    required this.current,
    this.onEdit,
  });

  final Future<List<DueRevision>> Function() load;

  /// The deadline in force; a change reloads the list.
  final DateTime? current;

  /// Corrects round n; null keeps them fixed.
  final void Function(int revision, DateTime due)? onEdit;

  @override
  State<DueRevisionList> createState() => _DueRevisionListState();
}

class _DueRevisionListState extends State<DueRevisionList> {
  List<DueRevision> _rounds = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(DueRevisionList old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) unawaited(_load());
  }

  Future<void> _load() async {
    final r = await widget.load();
    if (mounted) setState(() => _rounds = r);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final r in _rounds)
          DueButton(
            key: Key('due-round-${r.revision}'),
            title: '${dueRoundLabel(r.revision)} · ${S.pickDue.t}',
            due: r.dueAt,
            onPicked: widget.onEdit == null
                ? null
                : (d) => widget.onEdit!(r.revision, d),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${dueRoundLabel(r.revision)}  ',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  TextSpan(
                    text: formatDate(r.dueAt),
                    style: TextStyle(
                      fontWeight: r == _rounds.last ? FontWeight.w700 : null,
                      decoration: widget.onEdit == null
                          ? null
                          : TextDecoration.underline,
                      decorationColor: c.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
