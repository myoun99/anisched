import 'package:flutter/material.dart';

/// A notice's one action (an undo, mostly).
typedef NoticeAction = ({String label, VoidCallback onPressed, Key? key});

/// How long a notice stays; one with an action a little longer.
const noticeTime = Duration(seconds: 4);
const noticeTimeWithAction = Duration(seconds: 7);

/// Every snack bar of the app: [text] (after [icon]), replacing the one
/// on screen, gone by itself after a few seconds — an action does not
/// keep it (Flutter's default would).
void showNotice(
  BuildContext context,
  String text, {
  Key? key,
  IconData? icon,
  NoticeAction? action,
}) {
  final ink = Theme.of(context).colorScheme.onInverseSurface;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: key,
        persist: false,
        duration: action == null ? noticeTime : noticeTimeWithAction,
        content: icon == null
            ? Text(text)
            : Row(
                spacing: 8,
                children: [
                  Icon(icon, size: 18, color: ink),
                  Flexible(child: Text(text)),
                ],
              ),
        action: switch (action) {
          final a? => SnackBarAction(
            key: a.key,
            label: a.label,
            onPressed: a.onPressed,
          ),
          null => null,
        },
      ),
    );
}
