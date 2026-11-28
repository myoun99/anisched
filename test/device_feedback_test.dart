import 'package:anisched/src/models/catalogue.dart';
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

  // The picked-task actions sit in the app-name bar, icon and name each,
  // as many as fit in pickPriority order; the rest wait behind ⋯. The
  // narrowest phone held upright and sideways (the bar shares the row
  // with the view switcher there) and a desktop.
  Future<void> pickOne(WidgetTester t) async {
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
  }

  void onBar(WidgetTester t, Size size, String key) {
    final rows = t.getRect(find.byKey(const Key('sheet-rows')));
    final r = t.getRect(find.byKey(Key(key)));
    expect(r.bottom, lessThanOrEqualTo(rows.top), reason: key);
    expect(r.right, lessThanOrEqualTo(size.width), reason: key);
    expect(r.left, greaterThanOrEqualTo(0), reason: key);
  }

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets('a phone shows done, ⋯ and ✕ at $size', (t) async {
      await pumpShell(t, size);
      expect(find.byKey(const Key('pick-clear')), findsNothing);
      await pickOne(t);
      for (final key in const [
        'picked-count',
        'apply-done',
        'pick-more',
        'pick-clear',
      ]) {
        onBar(t, size, key);
      }
      expect(find.text('완료'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('phone upright: ⋯ holds the rest, by name, and acts', (t) async {
    final store = await pumpShell(t, const Size(390, 844));
    final g = store.partGroups().firstWhere((g) => g.inHand > 0);
    await t.longPress(find.byKey(Key('line-${g.key}')).first);
    await t.pump();
    expect(find.byKey(const Key('apply-submitted')), findsNothing);
    expect(find.byKey(const Key('pick-drop')), findsNothing);
    await t.tap(find.byKey(const Key('pick-more')));
    await t.pump();
    for (final name in const ['제출', '작업중', '리테이크', '받음']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    await t.tap(find.byKey(const Key('apply-submitted')));
    await t.pump();
    await t.pump();
    final after = store
        .partGroups(includeDone: true)
        .firstWhere((x) => x.key == g.key);
    expect(after.tasks.every((x) => x.status == TaskStatus.submitted), isTrue);
    expect(find.byKey(const Key('pick-more')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a desktop shows every action by name, no ⋯', (t) async {
    const size = Size(1440, 900);
    await pumpShell(t, size);
    await pickOne(t);
    for (final key in const [
      'picked-count',
      'apply-in_progress',
      'apply-submitted',
      'apply-done',
      'pick-hold',
      'pick-drop',
      'pick-clear',
    ]) {
      onBar(t, size, key);
    }
    expect(find.byKey(const Key('pick-more')), findsNothing);
    expect(find.text('제출'), findsWidgets);
    expect(t.takeException(), isNull);
  });

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
