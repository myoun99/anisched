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
    this.onHandOff,
    this.allHandedOff,
  });

  /// Takes the picked tasks off the user (引き上げ), or brings back ones
  /// already pulled; null hides it.
  final VoidCallback? onHandOff;
  final bool Function()? allHandedOff;

  /// Puts the picked tasks on hold (or takes them off); null hides it.
  final VoidCallback? onHold;

  /// Whether every picked open task already waits (the button then
  /// releases them).
  final bool Function()? allWaiting;

  final TaskSelection selection;

  /// Moves the picked tasks to a status; null hides the action buttons'
  /// effect (read-only app).
  final ValueChanged<TaskStatus>? onApply;

  /// The icon a status action shows.
  static IconData iconOf(TaskStatus s) => switch (s) {
    TaskStatus.inProgress => Icons.brush_outlined,
    TaskStatus.submitted => Icons.send_outlined,
    TaskStatus.done => Icons.check_circle_outline,
    TaskStatus.received => Icons.inbox_outlined,
    TaskStatus.retake => Icons.replay,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final n = selection.count;
        final on = n > 0 && onApply != null;
        final waiting = allWaiting?.call() ?? false;
        final pulled = allHandedOff?.call() ?? false;
        final actions = <_Action>[
          for (final st in pickActions)
            _Action(
              Key('apply-${st.dbName}'),
              iconOf(st),
              st.label,
              on ? () => onApply!(st) : null,
            ),
          if (onHold != null)
            _Action(
              const Key('pick-hold'),
              waiting ? Icons.play_circle_outline : Icons.pause_circle_outline,
              waiting ? S.unhold.t : S.hold.t,
              n > 0 ? onHold : null,
            ),
          if (onHandOff != null)
            _Action(
              const Key('pick-drop'),
              pulled ? Icons.undo : Icons.person_remove_outlined,
              pulled ? S.undoDrop.t : S.dropped.t,
              n > 0 ? onHandOff : null,
            ),
          _Action(
            const Key('pick-clear'),
            Icons.close,
            S.clear.t,
            n > 0 ? selection.clear : null,
          ),
        ];
        // Words when they fit, icons alone (with their words as tooltips)
        // when they do not — never a sideways scroll.
        return LayoutBuilder(
          builder: (context, box) {
            final style = DefaultTextStyle.of(context).style;
            final full = _countWidth + _fullWidth(actions, style);
            final compact = full > box.maxWidth;
            final row = Row(
              mainAxisSize: MainAxisSize.min,
              spacing: compact ? 4 : 6,
              children: [
                _count(context, n, compact),
                for (final a in actions)
                  _ActionButton(
                    key: a.key,
                    icon: a.icon,
                    label: a.label,
                    iconOnly: compact,
                    onTap: a.onTap,
                  ),
              ],
            );
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: row,
            );
          },
        );
      },
    );
  }

  static const _countWidth = 56.0;

  static double _fullWidth(List<_Action> actions, TextStyle style) {
    var w = 0.0;
    for (final a in actions) {
      final t = TextPainter(
        text: TextSpan(text: a.label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      w += t.width + 16 + 4 + 22 + 6;
    }
    return w;
  }

  Widget _count(BuildContext context, int n, bool compact) {
    final c = AppColors.of(context);
    return SizedBox(
      width: compact ? 28 : _countWidth,
      child: Text(
        compact ? '$n' : S.items.f({'n': n}),
        key: const Key('picked-count'),
        textAlign: TextAlign.right,
        style: TextStyle(
          color: n > 0 ? null : c.faint,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.key, this.icon, this.label, this.onTap);

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Just the icon; the word becomes its tooltip.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = onTap != null;
    final button = InkWell(
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
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 7 : 10),
            child: Center(
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Icon(icon, size: 16, color: enabled ? null : c.faint),
                  if (!iconOnly)
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
    return iconOnly ? Tooltip(message: label, child: button) : button;
  }
}
