
import 'package:flutter/material.dart';

import '../controllers/registration.dart';
import '../models/number_style.dart';
import 'count_stepper.dart';
import 'instant.dart';
import 'pick_field.dart';
import 'text/strings.dart';
import 'theme.dart';
import 'widgets.dart';

/// Asks which cuts to add to a unit: a first number and a count (the
/// register screen's steppers), plus cuts typed by name (its 「+」), shown
/// as they will be saved. Numbers already in the episode ([taken]) are
/// marked and block saving, as on the register screen. Returns the cut
/// names, or null when cancelled.
Future<List<String>?> askNewCuts(
  BuildContext context, {
  required NumberStyle style,
  required Set<String> taken,
}) => showInstantDialog<List<String>>(
  context: context,
  builder: (_) => _AddCuts(style: style, taken: taken),
);

class _AddCuts extends StatefulWidget {
  const _AddCuts({required this.style, required this.taken});

  final NumberStyle style;
  final Set<String> taken;

  @override
  State<_AddCuts> createState() => _AddCutsState();
}

class _AddCutsState extends State<_AddCuts> {
  /// The run starts after the episode's highest number in the style.
  late final _start = TextEditingController(text: '${_next()}');
  final _count = TextEditingController(text: '1');
  late CutDraft _cuts = _draft();

  int _next() {
    final run = RegExp('^${RegExp.escape(widget.style.prefix)}(\\d+)\$');
    var top = 0;
    for (final n in widget.taken) {
      final m = run.firstMatch(n);
      final v = m == null ? null : int.tryParse(m[1]!);
      if (v != null && v > top) top = v;
    }
    return top + 1;
  }

  CutDraft _draft() => CutDraft(
    start: int.tryParse(_start.text) ?? 1,
    count: (int.tryParse(_count.text) ?? 1).clamp(1, 2000),
    prefix: widget.style.prefix,
    width: widget.style.digits,
  );

  void _rebuild() => setState(() {
    final extras = _cuts.extras;
    _cuts = _draft()..extras.addAll(extras);
  });

  Future<void> _byName() async {
    final name = await askName(
      context,
      title: S.addCut.t,
      prefix: widget.style.prefix,
    );
    if (name == null || !mounted) return;
    setState(() => _cuts.add(name));
  }

  @override
  void dispose() {
    _start.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cells = _cuts.cells;
    final clashes = _cuts.clashes(widget.taken);
    return AlertDialog(
      key: const Key('add-cuts'),
      scrollable: true,
      title: DialogTitle(Icons.add_box_outlined, S.addCut.t),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                CountStepper(
                  label: S.firstCut.t,
                  preview: _cuts.number(_cuts.start),
                  controller: _start,
                  fieldKey: const Key('add-start'),
                  onChanged: _rebuild,
                ),
                CountStepper(
                  label: S.cutCount.t,
                  preview: '~ ${_cuts.number(_cuts.start + _cuts.count - 1)}',
                  controller: _count,
                  fieldKey: const Key('add-count'),
                  onChanged: _rebuild,
                ),
              ],
            ),
            // What will be saved; a number already there in red.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final id in cells)
                      DecoratedBox(
                        key: Key('add-cell-$id'),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: clashes.contains(id) ? scheme.error : c.line,
                            width: clashes.contains(id) ? 1.6 : 1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Text(
                            _cuts.label(id),
                            style: TextStyle(
                              fontSize: 11,
                              color: clashes.contains(id) ? scheme.error : null,
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      key: const Key('add-by-name'),
                      onTap: _byName,
                      borderRadius: BorderRadius.circular(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.add, size: 14, color: c.muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (clashes.isNotEmpty)
              Text(
                S.cutsTaken.f({
                  'names': [for (final id in clashes) _cuts.shown(id)]
                      .join(', '),
                }),
                key: const Key('add-clash'),
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel.t),
        ),
        FilledButton(
          key: const Key('add-ok'),
          onPressed: clashes.isEmpty && cells.isNotEmpty
              ? () =>
                    Navigator.of(context)
                        .pop([for (final id in cells) _cuts.valueOf(id)])
              : null,
          child: Text(S.ok.t),
        ),
      ],
    );
  }
}
