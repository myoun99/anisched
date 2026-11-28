import 'package:flutter/material.dart';

import 'instant.dart';

/// Makes a deadline tappable: a tap opens the date picker (at once, no
/// transition) and hands back the picked day, at the end of that day.
/// The one widget for every place a deadline shows (list, details, cut
/// chips, timeline); without [onPicked] it shows [child] as is.
/// The one date picker: it opens on [value]'s month with that day marked;
/// without one on [near] (the paired date: a deadline's start, a start's
/// deadline); without either on [today] (now).
Future<DateTime?> pickDay(
  BuildContext context, {
  required String title,
  DateTime? value,
  DateTime? near,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final at = (value ?? near ?? now).toLocal();
  final open = DateTime(at.year, at.month, at.day);
  final low = open.isBefore(now) ? open : now;
  final high = open.isAfter(now) ? open : now;
  return showInstantDatePicker(
    context: context,
    firstDate: DateTime(low.year - 2),
    lastDate: DateTime(high.year + 3, 12, 31),
    initialDate: open,
    title: title,
  );
}

class DueButton extends StatelessWidget {
  const DueButton({
    super.key,
    required this.due,
    required this.onPicked,
    required this.child,
    required this.title,
    this.near,
    this.longPress = false,
  });

  /// The date paired with this one (a deadline's start, a start's
  /// deadline): where the picker opens while [due] is empty.
  final DateTime? near;

  /// What is being picked, as the picker's heading (「마감 날짜」 …).
  final String title;

  final DateTime? due;
  final ValueChanged<DateTime>? onPicked;
  final Widget child;

  /// Open on a long press instead of a tap (where a tap already does
  /// something else, e.g. a cut chip).
  final bool longPress;

  Future<void> pick(BuildContext context) async {
    final cb = onPicked;
    if (cb == null) return;
    final d = await pickDay(context, title: title, value: due, near: near);
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
