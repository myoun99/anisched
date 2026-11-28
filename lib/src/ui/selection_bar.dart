import 'package:flutter/material.dart';

import '../models/catalogue.dart';
import 'format.dart';
import 'selection.dart';
import 'theme.dart';
import 'text/strings.dart';

/// Always-present strip for acting on picked tasks: the count, a button per
/// status, and clear. With nothing picked the buttons are disabled, so the
/// layout never shifts.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.selection,
    required this.onApply,
    this.onHold,
    this.allWaiting,
  });

  /// Puts the picked tasks on hold (or takes them off); null hides it.
  final VoidCallback? onHold;

  /// Whether every picked open task already waits (the button then
  /// releases them).
  final bool Function()? allWaiting;

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
                S.items.f({'n': n}),
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
            if (onHold != null)
              _ActionButton(
                key: const Key('pick-hold'),
                icon: (allWaiting?.call() ?? false)
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                label: (allWaiting?.call() ?? false) ? S.unhold.t : S.hold.t,
                onTap: n > 0 ? onHold : null,
              ),
            _ActionButton(
              key: const Key('pick-clear'),
              label: S.clear.t,
              onTap: n > 0 ? selection.clear : null,
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({super.key, required this.label, this.onTap, this.icon});

  final String label;
  final IconData? icon;
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  if (icon != null)
                    Icon(
                      icon,
                      size: 16,
                      color: enabled ? c.submitted : c.faint,
                    ),
                  Text(
                    label,
                    style: TextStyle(color: enabled ? null : c.faint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
