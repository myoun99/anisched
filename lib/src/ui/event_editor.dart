/// One window for a dated event (アフレコ, 打ち合わせ…), like a calendar
/// app's: title, an optional time, a note. The same window edits or
/// removes one.
library;

import 'package:flutter/material.dart';

import '../models/progress.dart';
import 'format.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// What the window answers: the event to save, or its removal.
sealed class EventAnswer {
  const EventAnswer();
}

class EventSave extends EventAnswer {
  const EventSave({required this.title, this.timeMinutes, this.note});

  final String title;

  /// Minutes past midnight; null = all day.
  final int? timeMinutes;
  final String? note;
}

class EventRemove extends EventAnswer {
  const EventRemove();
}

/// Opens the window for a new event on [day], or for [existing].
Future<EventAnswer?> showEventEditor(
  BuildContext context, {
  required DateTime day,
  EventRow? existing,
}) => showInstantDialog<EventAnswer>(
  context: context,
  builder: (_) => _EventEditor(day: day, existing: existing),
);

/// 「09:30」.
String eventTimeLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.day, this.existing});

  final DateTime day;
  final EventRow? existing;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _note = TextEditingController(text: widget.existing?.note);
  late int? _time = widget.existing?.timeMinutes;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final note = _note.text.trim();
    Navigator.of(context).pop<EventAnswer>(
      EventSave(
        title: title,
        timeMinutes: _time,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time == null
          ? const TimeOfDay(hour: 10, minute: 0)
          : TimeOfDay(hour: _time! ~/ 60, minute: _time! % 60),
      helpText: S.eventTime.t,
    );
    if (t != null) setState(() => _time = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: Row(
        spacing: 8,
        children: [
          const Icon(Icons.event_note_outlined),
          Text(formatDate(widget.day)),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            TextField(
              key: const Key('event-title'),
              controller: _title,
              autofocus: widget.existing == null,
              maxLength: 40,
              decoration: InputDecoration(labelText: S.eventTitle.t),
              onSubmitted: (_) => _save(),
            ),
            Row(
              spacing: 8,
              children: [
                Icon(Icons.schedule, size: 18, color: c.muted),
                TextButton(
                  key: const Key('event-time'),
                  onPressed: _pickTime,
                  child: Text(
                    _time == null ? S.allDay.t : eventTimeLabel(_time!),
                  ),
                ),
                if (_time != null)
                  IconButton(
                    key: const Key('event-all-day'),
                    tooltip: S.allDay.t,
                    onPressed: () => setState(() => _time = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
            TextField(
              key: const Key('event-note'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: S.eventNote.t),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton.icon(
            key: const Key('event-delete'),
            onPressed: () =>
                Navigator.of(context).pop<EventAnswer>(const EventRemove()),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(S.remove.t),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel.t),
        ),
        FilledButton(
          key: const Key('event-ok'),
          onPressed: _save,
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}
