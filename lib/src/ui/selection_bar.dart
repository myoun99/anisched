import 'package:flutter/material.dart';

import '../models/catalogue.dart';
import 'format.dart';
import 'instant.dart';
import 'selection.dart';
import 'theme.dart';
import 'text/strings.dart';
import 'widgets.dart';

/// The strip for acting on picked tasks: the count, the actions and
/// clear. As many actions as fit stand with their icon and words, most
/// used first ([pickPriority]); the rest open from ⋯ as a list with
/// words — never icons alone (a touch screen shows no tooltips).
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.selection,
    required this.onApply,
    this.onHold,
    this.allWaiting,
    this.onHandOff,
    this.allHandedOff,
    this.onDue,
  });

  /// Gives the picked cuts their own deadline (a new round each); null
  /// hides it.
  final VoidCallback? onDue;

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
        final actions =
            <_Action>[
              for (final st in pickActions)
                _Action(
                  st.dbName,
                  Key('apply-${st.dbName}'),
                  iconOf(st),
                  st.label,
                  on ? () => onApply!(st) : null,
                ),
              if (onDue != null)
                _Action(
                  'due',
                  const Key('pick-due'),
                  Icons.event_outlined,
                  S.due.t,
                  n > 0 ? onDue : null,
                ),
              if (onHold != null)
                _Action(
                  'hold',
                  const Key('pick-hold'),
                  waiting
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  waiting ? S.unhold.t : S.hold.t,
                  n > 0 ? onHold : null,
                ),
              if (onHandOff != null)
                _Action(
                  'drop',
                  const Key('pick-drop'),
                  pulled ? Icons.undo : Icons.person_remove_outlined,
                  pulled ? S.undoDrop.t : S.dropped.t,
                  n > 0 ? onHandOff : null,
                ),
            ]..sort(
              (a, b) => pickPriority
                  .indexOf(a.id)
                  .compareTo(pickPriority.indexOf(b.id)),
            );
        return LayoutBuilder(
          builder: (context, box) {
            final style = DefaultTextStyle.of(context).style;
            final shown = _fitting(actions, style, box.maxWidth);
            final rest = actions.skip(shown).toList();
            return Row(
              mainAxisSize: MainAxisSize.min,
              spacing: _gap,
              children: [
                _count(context, n),
                for (final a in actions.take(shown))
                  _ActionButton(
                    key: a.key,
                    icon: a.icon,
                    label: a.label,
                    onTap: a.onTap,
                  ),
                if (rest.isNotEmpty) _more(context, rest),
                _ActionButton(
                  key: const Key('pick-clear'),
                  icon: Icons.close,
                  label: S.clear.t,
                  iconOnly: true,
                  onTap: n > 0 ? selection.clear : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const _gap = 6.0;

  /// A square icon button (⋯, ✕).
  static const _square = 34.0;

  /// How many of [actions], in order, stand on the bar in [room]: all
  /// when all fit; else as many as leave room for ⋯ too.
  static int _fitting(List<_Action> actions, TextStyle style, double room) {
    const fixed = _countWidth + _gap + _square;
    final widths = [for (final a in actions) _width(a.label, style) + _gap];
    final all = widths.fold(0.0, (s, w) => s + w);
    if (fixed + all <= room) return actions.length;
    var used = fixed + _square + _gap;
    var n = 0;
    while (n < widths.length && used + widths[n] <= room) {
      used += widths[n];
      n++;
    }
    return n;
  }

  /// A button's width: padding, icon, gap, words.
  static double _width(String label, TextStyle style) {
    final t = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = t.width + 10 + 16 + 4 + 10;
    t.dispose();
    return w;
  }

  /// ⋯: the actions that did not fit, as a list with their words; one
  /// that cannot act now shows greyed.
  Widget _more(BuildContext context, List<_Action> rest) =>
      PopupMenuButton<VoidCallback>(
        key: const Key('pick-more'),
        tooltip: '',
        popUpAnimationStyle: instant,
        onSelected: (f) => f(),
        itemBuilder: (_) => [
          for (final a in rest)
            PopupMenuItem<VoidCallback>(
              key: a.key,
              enabled: a.onTap != null,
              value: a.onTap,
              child: MenuLine(
                icon: a.icon,
                label: a.label,
                enabled: a.onTap != null,
              ),
            ),
        ],
        child: const _ActionButton(
          icon: Icons.more_horiz,
          label: '',
          iconOnly: true,
          onTap: null,
          live: true,
        ),
      );

  static const _countWidth = 56.0;

  Widget _count(BuildContext context, int n) {
    final c = AppColors.of(context);
    return SizedBox(
      width: _countWidth,
      child: Text(
        S.items.f({'n': n}),
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
  const _Action(this.id, this.key, this.icon, this.label, this.onTap);

  /// Its place in [pickPriority].
  final String id;
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
    this.live = false,
  });

  /// Drawn as usable without a tap of its own (⋯: its menu takes the tap).
  final bool live;

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Just the icon; the word becomes its tooltip.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = live || onTap != null;
    final face = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 34,
        width: iconOnly ? SelectionBar._square : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 10),
          child: Center(
            widthFactor: iconOnly ? null : 1,
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
    );
    if (live) return face;
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: face,
    );
    return iconOnly && label.isNotEmpty
        ? Tooltip(message: label, child: button)
        : button;
  }
}
