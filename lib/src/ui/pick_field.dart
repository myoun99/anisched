import 'dart:async';

import 'package:flutter/material.dart';

import 'fit_text.dart';
import 'instant.dart';
import 'theme.dart';
import 'text/strings.dart';

/// One choice in a [PickField] list.
typedef PickOption<T> = ({T value, String title, String? note});

/// A field that picks one existing item or makes a new one, in the way
/// accounting apps pick a client (freee's 取引先): tapping opens the
/// [showCenteredPicker] list of what is registered, searchable, with
/// 「+ 새로 만들기」 at the bottom that makes the typed name on the spot.
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
    this.current,
  });

  /// The picked item's value, so the list opens centred on it.
  final T? current;

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
    final picked = await showCenteredPicker<T>(
      context: context,
      title: label,
      search: search,
      current: current,
      onCreate: onCreate,
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

/// THE way the app picks from a list that has a value now — like a date
/// picker: the list in its own order (cut names naturally sorted …) with
/// the current item in the middle, marked, so the next one is right under
/// it. Optional search and 「+ 새로 만들기」. Used by every pick: the
/// register fields, the time bar's cut, title and episode.
Future<PickOption<T>?> showCenteredPicker<T>({
  required BuildContext context,
  required String title,
  required Future<List<PickOption<T>>> Function(String query) search,
  T? current,
  Future<PickOption<T>?> Function(String name)? onCreate,
  bool searchable = true,
}) => showInstantDialog<PickOption<T>>(
  context: context,
  builder: (_) => _PickDialog<T>(
    title: title,
    search: search,
    current: current,
    onCreate: onCreate,
    searchable: searchable,
  ),
);

class _PickDialog<T> extends StatefulWidget {
  const _PickDialog({
    required this.title,
    required this.search,
    this.current,
    this.onCreate,
    this.searchable = true,
  });

  final String title;
  final Future<List<PickOption<T>>> Function(String query) search;
  final T? current;
  final Future<PickOption<T>?> Function(String name)? onCreate;
  final bool searchable;

  @override
  State<_PickDialog<T>> createState() => _PickDialogState<T>();
}

class _PickDialogState<T> extends State<_PickDialog<T>> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  List<PickOption<T>> _options = const [];
  int _asked = 0;
  final _scroll = ScrollController();
  bool _centred = false;

  static const _row = 44.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Once, after the list first shows: the current item to the middle.
  void _centre() {
    if (_centred || widget.current == null) return;
    final i = _options.indexWhere((o) => o.value == widget.current);
    if (i < 0) return;
    _centred = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      final to = (i * _row - (p.viewportDimension - _row) / 2).clamp(
        0.0,
        p.maxScrollExtent,
      );
      _scroll.jumpTo(to);
    });
  }

  Future<void> _load() async {
    final n = ++_asked;
    final o = await widget.search(_query.text.trim());
    if (mounted && n == _asked) {
      setState(() => _options = o);
      _centre();
    }
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
            if (!widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  widget.title,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  onTapOutside: unfocusOutside,
                  key: const Key('pick-search'),
                  controller: _query,
                  focusNode: _focus,
                  // Typing first only when nothing is picked yet; otherwise
                  // the list (and the next item) comes first.
                  autofocus: widget.current == null,
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
              child: ListView.builder(
                controller: _scroll,
                shrinkWrap: true,
                itemExtent: _row,
                itemCount: _options.length,
                itemBuilder: (context, i) {
                  final o = _options[i];
                  final now =
                      widget.current != null && o.value == widget.current;
                  return Material(
                    color: now ? c.selected : Colors.transparent,
                    child: ListTile(
                      key: now
                          ? const Key('pick-current')
                          : Key('pick-option-$i'),
                      dense: true,
                      title: FitText(
                        o.title,
                        style: TextStyle(
                          fontWeight: now ? FontWeight.w700 : null,
                        ),
                      ),
                      trailing: o.note == null
                          ? null
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: FitText(
                                o.note!,
                                textAlign: TextAlign.right,
                                style: TextStyle(color: c.muted),
                              ),
                            ),
                      onTap: () => Navigator.of(context).pop(o),
                    ),
                  );
                },
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
                  title: Text(
                    typed.isEmpty
                        ? S.createNew.t
                        : S.createNamed.f({'name': typed}),
                  ),
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
        child: Text(S.cancel.t),
      ),
      FilledButton(
        key: const Key('name-ok'),
        onPressed: () => Navigator.of(context).pop(_ctl.text),
        child: Text(S.ok.t),
      ),
    ],
  );
}
