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

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('the picked-task bar has its own space at $size', (t) async {
      await pumpShell(t, size);
      final bar = t.getRect(find.byKey(const Key('picked-count')));
      final rows = t.getRect(find.byKey(const Key('sheet-rows')));
      expect(bar.bottom, lessThanOrEqualTo(rows.top));
      final sheet = find.byKey(const Key('sheet-rows'));
      expect(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('picked-count')),
        ),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('tapping outside a number field ends editing', (t) async {
    await pumpShell(t, const Size(390, 844), view: AppView.register);
    final count = find.byKey(const Key('reg-count'));
    await t.ensureVisible(count);
    await t.tap(count);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
    expect(t.testTextInput.isVisible, isTrue);
    await t.tapAt(t.getTopLeft(count) - const Offset(0, 40));
    await t.pump();
    expect(t.testTextInput.isVisible, isFalse);
  });
}
