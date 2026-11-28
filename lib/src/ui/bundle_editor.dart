import 'package:flutter/material.dart';

import '../controllers/unit_actions.dart';
import '../services/catalogue_reader.dart';
import 'client_pick.dart';
import 'instant.dart';
import 'pick_field.dart';
import 'text/strings.dart';
import 'theme.dart';

/// Edits a picked bundle (one work · episode · part), shaped like the
/// event dialog: the client (picked or made, coloured — the register
/// screen's picker), the work's title, the episode's number and
/// subtitle, the part's name when it has one. Null when cancelled.
Future<BundleEdit?> editBundle(
  BuildContext context, {
  required BundleEdit initial,
  required String? clientName,
  required CatalogueReader? reader,
  int Function(String name)? onCreateClient,
  void Function(int clientId, int argb)? onClientColor,
}) => showInstantDialog<BundleEdit>(
  context: context,
  builder: (_) => _BundleEditor(
    initial: initial,
    clientName: clientName,
    reader: reader,
    onCreateClient: onCreateClient,
    onClientColor: onClientColor,
  ),
);

class _BundleEditor extends StatefulWidget {
  const _BundleEditor({
    required this.initial,
    required this.clientName,
    required this.reader,
    this.onCreateClient,
    this.onClientColor,
  });

  final BundleEdit initial;
  final String? clientName;
  final CatalogueReader? reader;
  final int Function(String name)? onCreateClient;
  final void Function(int clientId, int argb)? onClientColor;

  @override
  State<_BundleEditor> createState() => _BundleEditorState();
}

class _BundleEditorState extends State<_BundleEditor> {
  late PickOption<int>? _client = switch (widget.initial.clientId) {
    final id? => (value: id, title: widget.clientName ?? '', note: null),
    null => null,
  };
  final _colors = <int, int?>{};
  late final _work = TextEditingController(text: widget.initial.workTitle);
  late final _number = TextEditingController(
    text: widget.initial.episodeNumber,
  );
  late final _subtitle = TextEditingController(
    text: widget.initial.episodeTitle ?? '',
  );
  late final _part = TextEditingController(
    text: widget.initial.partLabel ?? '',
  );

  @override
  void dispose() {
    for (final c in [_work, _number, _subtitle, _part]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready =>
      _work.text.trim().isNotEmpty &&
      _number.text.trim().isNotEmpty &&
      (widget.initial.partLabel == null || _part.text.trim().isNotEmpty);

  void _save() {
    if (!_ready) return;
    final sub = _subtitle.text.trim();
    Navigator.of(context).pop<BundleEdit>((
      clientId: _client?.value,
      workTitle: _work.text.trim(),
      episodeNumber: _number.text.trim(),
      episodeTitle: sub.isEmpty ? null : sub,
      partLabel: widget.initial.partLabel == null ? null : _part.text.trim(),
    ));
  }

  Widget _field(String key, TextEditingController c, String label) => TextField(
    key: Key(key),
    controller: c,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
    onSubmitted: (_) => _save(),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      key: const Key('bundle-editor'),
      scrollable: true,
      title: Row(
        spacing: 8,
        children: [const Icon(Icons.edit_outlined), Text(S.edit.t)],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            ClientPick(
              picked: _client,
              reader: widget.reader,
              colors: _colors,
              width: 200,
              onPicked: (x) => setState(() => _client = x),
              onCreate: widget.onCreateClient,
              onColor: widget.onClientColor == null
                  ? null
                  : (id, argb) {
                      widget.onClientColor!(id, argb);
                      setState(() {});
                    },
            ),
            _field('edit-work', _work, S.title.t),
            Text(
              S.editWorkWide.t,
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
            Row(
              spacing: 10,
              children: [
                SizedBox(
                  width: 90,
                  child: _field('edit-episode', _number, S.episode.t),
                ),
                Expanded(
                  child: _field('edit-subtitle', _subtitle, S.subtitle.t),
                ),
              ],
            ),
            if (widget.initial.partLabel != null)
              _field('edit-part', _part, S.part.t),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel.t),
        ),
        FilledButton(
          key: const Key('edit-ok'),
          onPressed: _ready ? _save : null,
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}
