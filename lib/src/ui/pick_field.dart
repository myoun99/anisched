import 'dart:async';

import 'package:flutter/material.dart';

import 'instant.dart';
import 'theme.dart';

/// One choice in a [PickField] list.
typedef PickOption<T> = ({T value, String title, String? note});

/// A field that picks one existing item or makes a new one, in the way
/// accounting apps pick a client (freee's 取引先): tapping opens a
/// searchable list of what is registered, with 「+ 새로 만들기」 at the
/// bottom that makes the typed name on the spot.
class PickField<T> extends StatelessWidget {
  const PickField({
    super.key,
    required this.label,
    required this.value,
    required this.search,
    required this.onPicked,
    this.onCreate,
    this.enabled = true,
    this.width = 220,
  });

  final String label;

  /// What is picked now, as shown; null shows a dash.
  final String? value;

  /// Options matching the typed text (empty text: the usual list).
  final Future<List<PickOption<T>>> Function(String query) search;
  final ValueChanged<PickOption<T>> onPicked;

  /// Makes a new item from the typed name; null hides 「새로 만들기」.
  final Future<PickOption<T>?> Function(String name)? onCreate;
  final bool enabled;
  final double width;

  Future<void> _open(BuildContext context) async {
    final picked = await showInstantDialog<PickOption<T>>(
      context: context,
      builder: (_) =>
          _PickDialog<T>(title: label, search: search, onCreate: onCreate),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? () => _open(context) : null,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: enabled ? c.panel : c.panelAlt,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: value == null ? c.faint : null),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 20, color: c.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickDialog<T> extends StatefulWidget {
  const _PickDialog({required this.title, required this.search, this.onCreate});

  final String title;
  final Future<List<PickOption<T>>> Function(String query) search;
  final Future<PickOption<T>?> Function(String name)? onCreate;

  @override
  State<_PickDialog<T>> createState() => _PickDialogState<T>();
}

class _PickDialogState<T> extends State<_PickDialog<T>> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  List<PickOption<T>> _options = const [];
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final n = ++_asked;
    final o = await widget.search(_query.text.trim());
    if (mounted && n == _asked) setState(() => _options = o);
  }

  Future<void> _create() async {
    final name = _query.text.trim();
    if (name.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final made = await widget.onCreate!(name);
    if (mounted && made != null) Navigator.of(context).pop(made);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final typed = _query.text.trim();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onTapOutside: unfocusOutside,
                key: const Key('pick-search'),
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: widget.title,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {});
                  unawaited(_load());
                },
                onSubmitted: (_) {
                  if (_options.length == 1) {
                    Navigator.of(context).pop(_options.single);
                  }
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in _options)
                    ListTile(
                      dense: true,
                      title: Text(o.title),
                      trailing: o.note == null
                          ? null
                          : Text(o.note!, style: TextStyle(color: c.muted)),
                      onTap: () => Navigator.of(context).pop(o),
                    ),
                ],
              ),
            ),
            if (widget.onCreate != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: ListTile(
                  key: const Key('pick-create'),
                  dense: true,
                  leading: const Icon(Icons.add, size: 18),
                  title: Text(typed.isEmpty ? '새로 만들기' : '「$typed」 새로 만들기'),
                  onTap: _create,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small dialog asking for one name (a cut added or renamed by hand).
Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showInstantDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, style: const TextStyle(fontSize: 15)),
    content: TextField(
      onTapOutside: unfocusOutside,
      key: const Key('name-input'),
      controller: _ctl,
      autofocus: true,
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const Key('name-ok'),
        onPressed: () => Navigator.of(context).pop(_ctl.text),
        child: const Text('확인'),
      ),
    ],
  );
}
