import 'package:flutter/material.dart';

/// Popups and dialogs open and close at once, with no transition (the
/// user found the default animations slow). Every menu, picker and dialog
/// in the app goes through these.
const AnimationStyle instant = AnimationStyle.noAnimation;

/// [showDialog] without the fade.
Future<T?> showInstantDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) =>
    showDialog<T>(context: context, animationStyle: instant, builder: builder);

/// [showDatePicker] without the fade.
Future<DateTime?> showInstantDatePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialDate,
  String? title,
}) => showInstantDialog<DateTime>(
  context: context,
  builder: (_) => DatePickerDialog(
    firstDate: firstDate,
    lastDate: lastDate,
    initialDate: initialDate,
    helpText: title,
  ),
);

/// Every text field ends editing when the user taps anywhere outside it
/// (the value is already kept by its onChanged); pass to `onTapOutside`.
void unfocusOutside(PointerDownEvent _) =>
    FocusManager.instance.primaryFocus?.unfocus();
