import 'package:flutter/material.dart';

import '../controllers/registration.dart';
import 'count_stepper.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// The tools that fill a list of new cuts ([draft]): first cut ~ last cut
/// and 「범위로 추가」, then a name and 「직접 추가」 (12A, BANK). After an
/// add its fields empty and the first takes the focus again. The register
/// screen and a card's 「+」 use this one.
class CutAddTools extends StatefulWidget {
  const CutAddTools({
    super.key,
    required this.draft,
    required this.onChanged,
    this.first,
  });

  final CutDraft draft;

  /// After cuts were added.
  final VoidCallback onChanged;

  /// The first cut the range field starts with (the next free number).
  final int? first;

  @override
  State<CutAddTools> createState() => _CutAddToolsState();
}

class _CutAddToolsState extends State<CutAddTools> {
  late final _first = TextEditingController(text: '${widget.first ?? ''}');
  final _last = TextEditingController();
  final _name = TextEditingController();
  final _firstFocus = FocusNode();
  final _nameFocus = FocusNode();

  int? get _a => int.tryParse(_first.text.trim());
  int? get _b => int.tryParse(_last.text.trim());

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _name.dispose();
    _firstFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _addRange() {
    final a = _a;
    final b = _b ?? a;
    if (a == null || b == null) return;
    widget.draft.addRange(a, b);
    setState(() {
      _first.clear();
      _last.clear();
    });
    _firstFocus.requestFocus();
    widget.onChanged();
  }

  void _addOne() {
    if (!widget.draft.add(_name.text)) return;
    setState(_name.clear);
    _nameFocus.requestFocus();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = widget.draft;
    final a = _a;
    final b = _b;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            CountStepper(
              label: S.firstCut.t,
              preview: a == null ? '' : d.number(a),
              controller: _first,
              focusNode: _firstFocus,
              fieldKey: const Key('reg-first'),
              onChanged: () => setState(() {}),
            ),
            CountStepper(
              label: S.lastCut.t,
              preview: b == null ? '' : d.number(b),
              controller: _last,
              fieldKey: const Key('reg-last'),
              onChanged: () => setState(() {}),
              onSubmitted: _addRange,
            ),
            FilledButton.tonalIcon(
              key: const Key('cut-add-range'),
              onPressed: a == null ? null : _addRange,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: Text(S.addRange.t),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                key: const Key('cut-add-name'),
                controller: _name,
                focusNode: _nameFocus,
                onTapOutside: unfocusOutside,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _addOne(),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: d.prefix,
                  hintText: '12A',
                  hintStyle: TextStyle(color: c.faint),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('cut-add-one'),
              onPressed: _name.text.trim().isEmpty ? null : _addOne,
              icon: const Icon(Icons.add, size: 18),
              label: Text(S.addOne.t),
            ),
          ],
        ),
      ],
    );
  }
}
