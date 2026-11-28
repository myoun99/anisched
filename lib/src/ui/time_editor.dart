/// Fixing recorded time by hand: the stretches of one cut, each start and
/// end a button, a bin to drop one, + to add one (a timer left on while
/// asleep, work done away from the app).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/work_interval.dart';
import '../services/work_timer.dart';
import 'format.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// What the editor writes through; each may throw
/// [IntervalOverlapException] or [ArgumentError] (stop before start, in
/// the future), shown to the user instead of written.
class TimeEdits {
  const TimeEdits({
    required this.load,
    required this.edit,
    required this.add,
    required this.delete,
  });

  final Future<List<WorkInterval>> Function() load;
  final void Function(int id, {DateTime? start, DateTime? stop}) edit;
  final void Function(DateTime start, DateTime stop) add;
  final void Function(int id) delete;
}

/// Opens the stretches of a cut, titled [title] (the cut's name).
Future<void> showTimeEditor(
  BuildContext context, {
  required String title,
  required TimeEdits edits,
  required DateTime now,
}) => showInstantDialog<void>(
  context: context,
  builder: (_) => _TimeEditor(title: title, edits: edits, now: now),
);

/// A day, then a time of that day.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  required DateTime initial,
  required String title,
}) async {
  final d = await showInstantDatePicker(
    context: context,
    firstDate: DateTime(initial.year - 1),
    lastDate: DateTime(initial.year + 1),
    initialDate: initial,
    title: title,
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: title,
  );
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

class _TimeEditor extends StatefulWidget {
  const _TimeEditor({
    required this.title,
    required this.edits,
    required this.now,
  });

  final String title;
  final TimeEdits edits;
  final DateTime now;

  @override
  State<_TimeEditor> createState() => _TimeEditorState();
}

class _TimeEditorState extends State<_TimeEditor> {
  List<WorkInterval> _stretches = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final s = await widget.edits.load();
    if (mounted) setState(() => _stretches = s);
  }

  /// Runs one change; a refused one shows why and changes nothing.
  Future<void> _try(void Function() change) async {
    try {
      change();
      setState(() => _error = null);
    } on IntervalOverlapException {
      setState(() => _error = S.timeOverlap.t);
    } on ArgumentError {
      setState(() => _error = S.timeInvalid.t);
    }
    await _reload();
  }

  static String _at(DateTime t) {
    final l = t.toLocal();
    return '${formatDate(l)} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pick(WorkInterval w, {required bool start}) async {
    final was = (start ? w.start : (w.stop ?? widget.now)).toLocal();
    final at = await pickDateTime(
      context,
      initial: was,
      title: start ? S.timeStart.t : S.timeStop.t,
    );
    if (at == null || !mounted) return;
    await _try(
      () => start
          ? widget.edits.edit(w.id, start: at)
          : widget.edits.edit(w.id, stop: at),
    );
  }

  Future<void> _add() async {
    final start = await pickDateTime(
      context,
      initial: widget.now.subtract(const Duration(hours: 1)),
      title: S.timeStart.t,
    );
    if (start == null || !mounted) return;
    final stop = await pickDateTime(
      context,
      initial: start.add(const Duration(hours: 1)),
      title: S.timeStop.t,
    );
    if (stop == null || !mounted) return;
    await _try(() => widget.edits.add(start, stop));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final total = _stretches.fold(
      Duration.zero,
      (sum, w) => sum + (w.stop ?? widget.now).difference(w.start),
    );
    return AlertDialog(
      title: Text('${widget.title} · ${S.editTime.t}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            for (final w in _stretches)
              Row(
                key: Key('stretch-${w.id}'),
                spacing: 4,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          key: Key('stretch-start-${w.id}'),
                          onPressed: () => _pick(w, start: true),
                          child: Text(_at(w.start)),
                        ),
                        const Text('–'),
                        TextButton(
                          key: Key('stretch-stop-${w.id}'),
                          onPressed: w.stop == null
                              ? null
                              : () => _pick(w, start: false),
                          child: Text(w.stop == null ? '…' : _at(w.stop!)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatWorked((w.stop ?? widget.now).difference(w.start)),
                    style: TextStyle(color: c.muted),
                  ),
                  IconButton(
                    key: Key('stretch-delete-${w.id}'),
                    tooltip: S.remove.t,
                    onPressed: () => _try(() => widget.edits.delete(w.id)),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                key: const Key('stretch-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('stretch-add'),
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: Text(S.add.t),
              ),
            ),
          ],
        ),
      ),
      actions: [
        Text(formatWorked(total), style: TextStyle(color: c.muted)),
        FilledButton(
          key: const Key('stretch-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}
