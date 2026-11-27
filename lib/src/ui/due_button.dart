import 'package:flutter/material.dart';

import 'instant.dart';

/// Makes a deadline tappable: a tap opens the date picker (at once, no
/// transition) and hands back the picked day, at the end of that day.
/// The one widget for every place a deadline shows (list, details, cut
/// chips, timeline); without [onPicked] it shows [child] as is.
class DueButton extends StatelessWidget {
  const DueButton({
    super.key,
    required this.due,
    required this.onPicked,
    required this.child,
    this.longPress = false,
  });

  final DateTime? due;
  final ValueChanged<DateTime>? onPicked;
  final Widget child;

  /// Open on a long press instead of a tap (where a tap already does
  /// something else, e.g. a cut chip).
  final bool longPress;

  Future<void> pick(BuildContext context) async {
    final cb = onPicked;
    if (cb == null) return;
    final now = DateTime.now();
    final d = await showInstantDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDate: (due ?? now).toLocal(),
    );
    if (d != null) cb(DateTime(d.year, d.month, d.day, 23, 59));
  }

  @override
  Widget build(BuildContext context) {
    if (onPicked == null) return child;
    if (longPress) {
      return GestureDetector(onLongPress: () => pick(context), child: child);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => pick(context),
      child: child,
    );
  }
}
