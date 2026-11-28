import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide UndoHistory;
import 'package:flutter/services.dart';

import '../services/device_settings.dart';
import '../services/undo_history.dart';
import 'text/strings.dart';

/// Apple keyboards: `Cmd` for `Ctrl`.
bool get appleKeys =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// This device's key combinations per action ([ShortcutAction]); main
/// fills it from [DeviceSettings] and [saveShortcut] writes back.
final shortcutKeys = ValueNotifier<Map<String, List<String>>>(
  defaultShortcuts(apple: appleKeys),
);

/// Sets [action]'s keys (null: the default). Main points it at
/// [DeviceSettings.setShortcut]; alone it changes [shortcutKeys] only.
void Function(String action, List<String>? keys) saveShortcut = (a, keys) {
  shortcutKeys.value = {
    ...shortcutKeys.value,
    a: keys ?? defaultShortcuts(apple: appleKeys)[a] ?? const [],
  };
};

/// `Ctrl+Shift+Z` as an activator; null when unreadable.
SingleActivator? parseKeys(String text) {
  final parts = text.split('+');
  final name = parts.last.toUpperCase();
  final key = LogicalKeyboardKey.knownLogicalKeys
      .where((k) => k.keyLabel.toUpperCase() == name)
      .firstOrNull;
  if (key == null) return null;
  final mods = parts.sublist(0, parts.length - 1).toSet();
  return SingleActivator(
    key,
    control: mods.contains('Ctrl'),
    meta: mods.contains('Cmd'),
    shift: mods.contains('Shift'),
    alt: mods.contains('Alt'),
  );
}

/// The keys held now with [key], as `Ctrl+Shift+Z`; null for a modifier
/// alone (still choosing).
String? keysOf(LogicalKeyboardKey key) {
  final modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };
  if (modifiers.contains(key) || key.keyLabel.isEmpty) return null;
  final k = HardwareKeyboard.instance;
  return [
    if (k.isControlPressed) 'Ctrl',
    if (k.isMetaPressed) 'Cmd',
    if (k.isAltPressed) 'Alt',
    if (k.isShiftPressed) 'Shift',
    key.keyLabel.toUpperCase(),
  ].join('+');
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

/// Runs [run] for its intent, unless a text field has the focus: then
/// the keys go on to the field's own undo (its typing, not the app's).
class _HistoryAction<T extends Intent> extends Action<T> {
  _HistoryAction(this.run);

  final VoidCallback run;

  static bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  @override
  bool isEnabled(T intent) => !_typing;

  @override
  Object? invoke(T intent) {
    run();
    return null;
  }
}

/// The app's undo and redo keys over [child] ([shortcutKeys]), calling
/// [onUndo] and [onRedo]. Holds a focus of its own so the keys work with
/// nothing else focused.
class UndoKeys extends StatelessWidget {
  const UndoKeys({
    super.key,
    required this.onUndo,
    required this.onRedo,
    required this.child,
  });

  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, List<String>>>(
        valueListenable: shortcutKeys,
        builder: (context, keys, child) => Shortcuts(
          shortcuts: {
            for (final (action, intent) in const [
              (ShortcutAction.undo, _UndoIntent()),
              (ShortcutAction.redo, _RedoIntent()),
            ])
              for (final k in keys[action] ?? const <String>[])
                ?parseKeys(k): intent,
          },
          child: child!,
        ),
        child: Actions(
          actions: {
            _UndoIntent: _HistoryAction<_UndoIntent>(onUndo),
            _RedoIntent: _HistoryAction<_RedoIntent>(onRedo),
          },
          child: Focus(autofocus: true, child: child),
        ),
      );
}

/// ↶ ↷ for touch: icons only (the word is the tooltip), greyed with
/// nothing to undo or redo. Follows [history].
class UndoButtons extends StatelessWidget {
  const UndoButtons({
    super.key,
    required this.history,
    required this.onUndo,
    required this.onRedo,
  });

  final UndoHistory history;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: history.changes,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (key, icon, word, can, run) in [
          ('undo', Icons.undo, S.undo.t, history.canUndo, onUndo),
          ('redo', Icons.redo, S.redo.t, history.canRedo, onRedo),
        ])
          IconButton(
            key: Key(key),
            tooltip: word,
            onPressed: can ? run : null,
            icon: Icon(icon, size: 20),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
          ),
      ],
    ),
  );
}
