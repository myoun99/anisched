import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpShell(
  WidgetTester t,
  Size size, {
  AppView view = AppView.list,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
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
  return store;
}

/// Whether the route showing [f] is fully open after one frame.
bool settled(WidgetTester t, Finder f) =>
    ModalRoute.of(t.element(f))!.animation!.status == AnimationStatus.completed;

void main() {
  setUp(() {
    Folds.cutsInDetails.value = true;
    Folds.newCuts.value = true;
    Folds.savedCuts.value = true;
  });

  testWidgets('the filter menu opens and closes with no transition', (t) async {
    await pumpShell(t, const Size(390, 844));
    await t.tap(find.byKey(const Key('filter-button')));
    await t.pump();
    expect(find.text('3일 안'), findsOneWidget);
    expect(settled(t, find.text('3일 안')), isTrue);
    await t.tap(find.text('3일 안'));
    await t.pump();
    expect(find.text('2주 안'), findsNothing, reason: 'gone in one frame');
  });

  testWidgets('pick fields and date pickers open with no transition', (
    t,
  ) async {
    await pumpShell(t, const Size(1280, 800), view: AppView.register);
    await t.tap(find.byKey(const Key('pick-work')));
    await t.pump();
    expect(settled(t, find.byKey(const Key('pick-search'))), isTrue);
    await t.tapAt(const Offset(5, 5));
    await t.pump();
    expect(find.byKey(const Key('pick-search')), findsNothing);
    await t.tap(find.byKey(const Key('reg-date-마감')));
    await t.pump();
    expect(settled(t, find.byType(DatePickerDialog)), isTrue);
  });

  // The picked-task actions sit in the app-name bar: every button on
  // screen without a sideways scroll — words on wide screens, icons alone
  // on a phone. The narrowest phone held upright and sideways (the bar
  // shares the row with the view switcher there) and a desktop.
  for (final (size, words) in const [
    (Size(390, 844), false),
    (Size(844, 390), false),
    (Size(1440, 900), true),
  ]) {
    testWidgets('the picked-task actions fit the top bar at $size', (t) async {
      await pumpShell(t, size);
      // Nothing picked: no actions at all.
      expect(find.byKey(const Key('pick-clear')), findsNothing);
      await t.longPress(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('line-'),
            )
            .first,
      );
      await t.pump();
      final rows = t.getRect(find.byKey(const Key('sheet-rows')));
      for (final key in const [
        'picked-count',
        'apply-in_progress',
        'apply-submitted',
        'apply-done',
        'pick-hold',
        'pick-drop',
        'pick-clear',
      ]) {
        final r = t.getRect(find.byKey(Key(key)));
        expect(r.bottom, lessThanOrEqualTo(rows.top), reason: key);
        expect(r.right, lessThanOrEqualTo(size.width), reason: key);
        expect(r.left, greaterThanOrEqualTo(0), reason: key);
      }
      expect(find.text('제출'), words ? findsWidgets : findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('tapping outside a number field ends editing', (t) async {
    await pumpShell(t, const Size(390, 844), view: AppView.register);
    final count = find.byKey(const Key('reg-count'));
    // Mid-screen, with room above it to tap outside.
    await Scrollable.ensureVisible(t.element(count), alignment: 0.5);
    await t.pump();
    await t.tap(count);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
    expect(t.testTextInput.isVisible, isTrue);
    // A sure empty spot beside the field: the plain 「컷 수」 caption.
    await t.tap(find.textContaining('컷 수', findRichText: true));
    await t.pump();
    expect(t.testTextInput.isVisible, isFalse);
  });
}
