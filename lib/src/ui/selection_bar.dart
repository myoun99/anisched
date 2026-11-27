import 'package:flutter/material.dart';

import '../models/catalogue.dart';
import 'format.dart';
import 'selection.dart';
import 'theme.dart';

/// Always-present strip for acting on picked tasks: the count, a button per
/// status, and clear. With nothing picked the buttons are disabled, so the
/// layout never shifts.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.selection,
    required this.onApply,
  });

  final TaskSelection selection;

  /// Moves the picked tasks to a status; null hides the action buttons'
  /// effect (read-only app).
  final ValueChanged<TaskStatus>? onApply;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final n = selection.count;
        final on = n > 0 && onApply != null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '$n건',
                key: const Key('picked-count'),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: n > 0 ? null : c.faint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            for (final s in pickActions)
              _ActionButton(
                key: Key('apply-${s.dbName}'),
                label: s.label,
                onTap: on ? () => onApply!(s) : null,
              ),
            _ActionButton(
              key: const Key('pick-clear'),
              label: '해제',
              onTap: n > 0 ? selection.clear : null,
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(color: enabled ? null : c.faint),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
