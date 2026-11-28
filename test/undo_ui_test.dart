import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/device_settings.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/undo.dart';
import 'package:flutter/material.dart' hide UndoHistory;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<(CatalogueStore, UndoHistory)> pumpShell(
  WidgetTester t, {
  AppView view = AppView.list,
}) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  shortcutKeys.value = defaultShortcuts(apple: false);
  addTearDown(() => shortcutKeys.value = defaultShortcuts(apple: false));
  final store = sampleCatalogue(now);
  final history = UndoHistory.attach(store.db);
  addTearDown(history.detach);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(
        initialView: view,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return (store, history);
}

/// Picks [g]'s line and marks it submitted: one write, one step.
Future<void> submit(WidgetTester t, PartGroup g) async {
  await t.longPress(find.byKey(Key('line-${g.key}')).first);
  await t.pump();
  await t.tap(find.byKey(const Key('apply-submitted')));
  await t.pump();
  await t.pump();
}

bool allSubmitted(CatalogueStore s, String key) => s
    .partGroups(includeDone: true)
    .firstWhere((x) => x.key == key)
    .tasks
    .every((x) => x.status == TaskStatus.submitted);

Future<void> keys(WidgetTester t, List<LogicalKeyboardKey> held) async {
  for (final k in held) {
    await t.sendKeyDownEvent(k);
  }
  for (final k in held.reversed) {
    await t.sendKeyUpEvent(k);
  }
  await t.pump();
  await t.pump();
}

VoidCallback? button(WidgetTester t, String key) =>
    t.widget<IconButton>(find.byKey(Key(key))).onPressed;

void main() {
  testWidgets('Ctrl+Z takes back the last change; the buttons follow', (
    t,
  ) async {
    final (store, _) = await pumpShell(t);
    expect(button(t, 'undo'), isNull, reason: 'nothing to undo yet');
    expect(button(t, 'redo'), isNull);
    final g = store.partGroups().firstWhere((g) => g.toSubmit > 0);
    await submit(t, g);
    expect(allSubmitted(store, g.key), isTrue);
    expect(button(t, 'undo'), isNotNull);

    await keys(t, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ]);
    expect(allSubmitted(store, g.key), isFalse, reason: 'undone');
    expect(button(t, 'redo'), isNotNull);

    // ↷ does it again.
    await t.tap(find.byKey(const Key('redo')));
    await t.pump();
    await t.pump();
    expect(allSubmitted(store, g.key), isTrue);
  });

  testWidgets('a changed key does the undo; the old one no longer', (t) async {
    final (store, _) = await pumpShell(t, view: AppView.settings);
    // Set in settings: tap the undo keys, press Ctrl+U.
    await t.tap(find.byKey(const Key('keys-undo')));
    await t.pump();
    await keys(t, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyU]);
    expect(shortcutKeys.value[ShortcutAction.undo], ['Ctrl+U']);
    expect(find.text('Ctrl+U'), findsOneWidget);

    await t.tap(find.byKey(const Key('view-tab-list')));
    await t.pump();
    final g = store.partGroups().firstWhere((g) => g.toSubmit > 0);
    await submit(t, g);
    await keys(t, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ]);
    expect(allSubmitted(store, g.key), isTrue, reason: 'Ctrl+Z is off now');
    await keys(t, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyU]);
    expect(allSubmitted(store, g.key), isFalse, reason: 'Ctrl+U undoes');
  });

  testWidgets('in a text field Ctrl+Z is the field\'s, not the app\'s', (
    t,
  ) async {
    final (store, history) = await pumpShell(t);
    final g = store.partGroups().firstWhere((g) => g.toSubmit > 0);
    await submit(t, g);
    await t.tap(find.byKey(const Key('view-tab-register')));
    await t.pump();
    await t.tap(find.byKey(const Key('reg-last')));
    await t.pump();
    await keys(t, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ]);
    expect(allSubmitted(store, g.key), isTrue);
    expect(history.canUndo, isTrue);
  });
}
