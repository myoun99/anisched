import 'package:flutter/material.dart';

import '../controllers/registration.dart';
import '../models/number_style.dart';
import 'cut_add_tools.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'widgets.dart';

/// Asks which cuts to add to a unit with the register screen's tools
/// ([CutAddTools]: a range, or one by name), shown as they will be saved. Numbers already in the episode ([taken]) are
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
  late final _cuts = CutDraft(
    count: 0,
    prefix: widget.style.prefix,
    width: widget.style.digits,
  );

  /// The range starts after the episode's highest number in the style.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cells = _cuts.cells;
    final clashes = _cuts.clashes(widget.taken);
    return AlertDialog(
      key: const Key('add-cuts'),
      scrollable: true,
      title: DialogTitle(Icons.add_box_outlined, S.addCut.t),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            CutAddTools(
              draft: _cuts,
              first: _next(),
              onChanged: () => setState(() {}),
            ),
            // What will be saved; a number already there in red.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final id in cells)
                      CutBlock(
                        key: Key('add-cell-$id'),
                        edge: clashes.contains(id) ? scheme.error : null,
                        children: [
                          Text(
                            _cuts.shown(id),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: clashes.contains(id) ? scheme.error : null,
                            ),
                          ),
                        ],
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
