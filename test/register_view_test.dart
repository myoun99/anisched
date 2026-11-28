import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Future<CatalogueStore> pumpRegister(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = sampleCatalogue(now);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const AlwaysScrollbarBehavior(),
      home: AppShell(
        initialView: AppView.register,
        reader: SyncCatalogueReader(store),
        store: store,
        clock: () => now,
      ),
    ),
  );
  await t.pump();
  return store;
}

void main() {
  setUp(() {
    Folds.cutsInDetails.value = true;
    Folds.newCuts.value = true;
    Folds.savedCuts.value = true;
    Folds.registerStages.value = false;
  });

  // Phones: language_test lays every tab out there.
  for (final size in const [Size(1440, 900)]) {
    testWidgets('register lays out at $size', (t) async {
      await pumpRegister(t, size);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('role-원화')), findsOneWidget);
      if (size.width >= 1100) {
        expect(find.byKey(const Key('cell-C001')), findsOneWidget);
      }
    });
  }

  testWidgets('a role checks its stages; a stage box toggles alone', (t) async {
    await pumpRegister(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('role-작감')));
    await t.pump();
    final lo = find.descendant(
      of: find.byKey(const Key('stage-LO/작감')),
      matching: find.byType(Checkbox),
    );
    expect(t.widget<Checkbox>(lo).value, isTrue);
    expect(find.text('공정 2개'), findsOneWidget);
    // Folded, a box unchecked leaves the row.
    await t.tap(find.byKey(const Key('stage-LO/작감')));
    await t.pump();
    expect(find.byKey(const Key('stage-LO/작감')), findsNothing);
    expect(find.text('공정 1개'), findsOneWidget);
    // Unfolded, every stage shows, checked or not.
    await t.tap(find.byKey(const Key('fold-stages')));
    await t.pump();
    expect(t.widget<Checkbox>(lo).value, isFalse);
    final boxes = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('stage-'),
    );
    expect(boxes.evaluate().length, greaterThan(2));
  });

  testWidgets('the roles sit on one sliding row', (t) async {
    await pumpRegister(t, const Size(390, 844));
    final roles = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('role-'),
    );
    expect(roles.evaluate().length, greaterThan(3));
    final tops = {
      for (final e in roles.evaluate())
        t.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(tops, hasLength(1));
    expect(
      find.ancestor(
        of: roles.first,
        matching: find.byKey(const Key('roles-row')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pick a work, make an episode, edit the grid, register', (
    t,
  ) async {
    final store = await pumpRegister(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('pick-work')));
    await t.pumpAndSettle();
    await t.tap(find.text('별빛 정류장').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-episode')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pick-search')), '#99');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-create')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('reg-count')), '10');
    await t.pump();
    expect(find.byKey(const Key('cell-C011')), findsNothing);

    final g = await t.startGesture(
      t.getCenter(find.byKey(const Key('cell-C002'))),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveTo(t.getCenter(find.byKey(const Key('cell-C003'))));
    await g.moveTo(t.getCenter(find.byKey(const Key('cell-C004'))));
    await g.up();
    await t.pump();
    await t.tap(find.byKey(const Key('cut-remove')));
    await t.pump();
    expect(find.text('7 cut'), findsOneWidget);

    await t.tap(find.byKey(const Key('cell-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name-input')), 'BANK1');
    await t.tap(find.byKey(const Key('name-ok')));
    await t.pumpAndSettle();
    expect(find.text('8 cut'), findsOneWidget);

    await t.tap(find.byKey(const Key('cell-C005')));
    await t.tap(find.byKey(const Key('cell-C006')));
    await t.pump();
    await t.tap(find.byKey(const Key('cut-share')));
    await t.pump();
    expect(find.text('8 cut'), findsOneWidget, reason: 'shared stays two');

    await t.tap(find.byKey(const Key('register')));
    await t.pump();
    await t.pump();
    final work = store.works().firstWhere((w) => w.title == '별빛 정류장');
    // Typed 「#99」: stored in the document's episode style.
    final ep = store.episodes(work.id).firstWhere((e) => e.number == '#99');
    final numbers = store.cuts(ep.id).map((c) => c.number).toSet();
    expect(numbers.length, 8);
    expect(numbers, contains('BANK1'));
  });

  testWidgets('an episode\'s saved cuts can be taken out and renamed', (
    t,
  ) async {
    final store = await pumpRegister(t, const Size(1440, 1400));
    await t.tap(find.byKey(const Key('pick-work')));
    await t.pumpAndSettle();
    await t.tap(find.text('별빛 정류장').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-episode')));
    await t.pumpAndSettle();
    await t.tap(find.text('#07').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('reg-count')), '1');
    await t.pump();
    final saved = find.byKey(const Key('saved-C014'));
    await t.ensureVisible(saved);
    await t.tap(saved);
    await t.pump();
    await t.tap(find.byKey(const Key('saved-remove')));
    await t.pump();
    await t.pump();
    final work = store.works().firstWhere((w) => w.title == '별빛 정류장');
    final ep = store.episodes(work.id).firstWhere((e) => e.number == '#07');
    expect(store.cuts(ep.id).map((c) => c.number), isNot(contains('C014')));
    expect(saved, findsOneWidget, reason: 'kept on the grid, crossed out');
    await t.tap(saved);
    await t.pump();
    await t.tap(find.byKey(const Key('saved-remove')));
    await t.pump();
    await t.pump();
    expect(store.cuts(ep.id).map((c) => c.number), contains('C014'));

    await t.tap(find.byKey(const Key('saved-C014')));
    await t.tap(find.byKey(const Key('saved-C015')));
    await t.pump();
    await t.tap(find.byKey(const Key('saved-share')));
    await t.pump();
    await t.pump();
    bool shared(String n) =>
        store.cuts(ep.id).firstWhere((c) => c.number == n).sharedLabel != null;
    expect(shared('C014'), isTrue);
    await t.tap(find.byKey(const Key('saved-C015')));
    await t.pump();
    await t.tap(find.byKey(const Key('saved-share')));
    await t.pump();
    await t.pump();
    expect(shared('C015'), isFalse);

    await t.tap(find.byKey(const Key('saved-C012')));
    await t.pump();
    await t.tap(find.byKey(const Key('saved-rename')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name-input')), 'C012X');
    await t.tap(find.byKey(const Key('name-ok')));
    await t.pumpAndSettle();
    expect(store.cuts(ep.id).map((c) => c.number), contains('C012X'));
  });
}
