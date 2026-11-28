import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/controllers/registration.dart';
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
    // No scrollbar under it, though the app's lists show theirs.
    expect(
      find.descendant(
        of: find.byKey(const Key('roles-row')),
        matching: find.byWidgetPredicate((w) => w is RawScrollbar),
      ),
      findsNothing,
    );
    expect(find.byWidgetPredicate((w) => w is RawScrollbar), findsWidgets);
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

  test('a renamed cell moves to its new number', () {
    final draft = CutDraft(count: 3)..rename('C001', 'C010');
    expect(draft.cells, ['C002', 'C003', 'C001']);
    expect(draft.shown('C001'), 'C010');
  });

  testWidgets('added cuts take their place at once: 7 · 12 · 12A · BANK', (
    t,
  ) async {
    await pumpRegister(t, const Size(1440, 900));
    await t.enterText(find.byKey(const Key('reg-count')), '1');
    await t.pump();
    for (final name in ['12', '7', 'BANK', '12A']) {
      await t.tap(find.byKey(const Key('cell-add')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('name-input')), name);
      await t.tap(find.byKey(const Key('name-ok')));
      await t.pumpAndSettle();
    }
    // The cells in reading order (one row here).
    final cells =
        find
            .byWidgetPredicate((w) {
              final k = w.key;
              return k is ValueKey<String> &&
                  k.value.startsWith('cell-') &&
                  k.value != 'cell-add';
            })
            .evaluate()
            .map((e) => (e.widget.key! as ValueKey<String>).value)
            .toList()
          ..sort((a, b) {
            final pa = t.getTopLeft(find.byKey(Key(a)));
            final pb = t.getTopLeft(find.byKey(Key(b)));
            return pa.dy != pb.dy
                ? pa.dy.compareTo(pb.dy)
                : pa.dx.compareTo(pb.dx);
          });
    expect(cells, ['cell-C001', 'cell-7', 'cell-12', 'cell-12A', 'cell-BANK']);
  });

  // LO and 原画 rarely share dates: each checked stage has its own row,
  // the stage above's dates copied down until set.
  testWidgets('each stage gets its own deadline row; set apart, kept apart', (
    t,
  ) async {
    final store = await pumpRegister(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('role-작감')));
    await t.pump();
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('reg-stage-dates-'),
    );
    expect(rows.evaluate().length, greaterThanOrEqualTo(2));
    String stageOf(int i) => (t.widget(rows.at(i)).key! as ValueKey<String>)
        .value
        .substring('reg-stage-dates-'.length);
    final first = stageOf(0);
    final second = stageOf(1);
    Future<void> pickDue(String stage, String day) async {
      await t.tap(find.byKey(Key('reg-due-$stage')));
      await t.pumpAndSettle();
      await t.tap(find.text(day).last);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
    }

    await pickDue(first, '10');
    // Copied down to the second stage, faint.
    Text dueText(String stage) => t.widget<Text>(
      find.descendant(
        of: find.byKey(Key('reg-due-$stage')),
        matching: find.byType(Text),
      ),
    );
    expect(dueText(second).data, dueText(first).data);
    await pickDue(second, '20');
    expect(dueText(second).data, isNot(dueText(first).data));

    await t.tap(find.byKey(const Key('pick-work')));
    await t.pumpAndSettle();
    await t.tap(find.text('별빛 정류장').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-episode')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pick-search')), '#98');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-create')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('reg-count')), '2');
    await t.pump();
    await t.tap(find.byKey(const Key('register')));
    await t.pump();
    await t.pump();
    final work = store.works().firstWhere((w) => w.title == '별빛 정류장');
    final ep = store.episodes(work.id).firstWhere((e) => e.number == '#98');
    final cards = store.partGroups().where((g) => g.episodeId == ep.id);
    DateTime dueOf(String stage) =>
        cards.firstWhere((g) => g.stageName == stage).dueAt!.toLocal();
    expect(dueOf(first).day, 10);
    expect(dueOf(second).day, 20);
  });

  /// The work picker's shown value: the picked work, or none.
  bool workPicked(WidgetTester t, String title) => find
      .descendant(
        of: find.byKey(const Key('pick-work')),
        matching: find.text(title),
      )
      .evaluate()
      .isNotEmpty;

  Future<void> pickWork(WidgetTester t) async {
    await t.tap(find.byKey(const Key('pick-work')));
    await t.pumpAndSettle();
    await t.tap(find.text('별빛 정류장').last);
    await t.pumpAndSettle();
  }

  testWidgets('the foot: reset on the left, register on the right', (t) async {
    await pumpRegister(t, const Size(390, 844));
    final reset = t.getRect(find.byKey(const Key('register-reset')));
    final add = t.getRect(find.byKey(const Key('register')));
    final tabs = t.getRect(find.byKey(const Key('view-switch')));
    expect(reset.left, lessThan(60));
    expect(add.right, greaterThan(390 - 60));
    expect((reset.center.dy - add.center.dy).abs(), lessThan(2));
    expect(add.bottom, lessThanOrEqualTo(tabs.top), reason: 'above the tabs');
    // Nothing to register yet: greyed.
    expect(
      t.widget<FilledButton>(find.byKey(const Key('register'))).onPressed,
      isNull,
    );
  });

  testWidgets('reset empties the form; its undo puts it back', (t) async {
    await pumpRegister(t, const Size(1440, 900));
    await pickWork(t);
    await t.enterText(find.byKey(const Key('reg-count')), '12');
    await t.pump();
    expect(workPicked(t, '별빛 정류장'), isTrue);
    await t.tap(find.byKey(const Key('register-reset')));
    await t.pump();
    expect(workPicked(t, '별빛 정류장'), isFalse);
    expect(find.text('100'), findsOneWidget, reason: 'the count as at first');
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('reset-undo')));
    await t.pump();
    await t.pump();
    expect(workPicked(t, '별빛 정류장'), isTrue);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a register starts the form over, with a note', (t) async {
    await pumpRegister(t, const Size(1440, 900));
    await pickWork(t);
    await t.tap(find.byKey(const Key('pick-episode')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pick-search')), '#97');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-create')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('reg-count')), '3');
    await t.pump();
    await t.tap(find.byKey(const Key('register')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('registered-snack')), findsOneWidget);
    expect(find.textContaining('3 cut'), findsWidgets);
    expect(workPicked(t, '별빛 정류장'), isFalse);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('a cell\'s name is edited as its value, the C outside', (
    t,
  ) async {
    await pumpRegister(t, const Size(1440, 900));
    await t.longPress(find.byKey(const Key('cell-C012')));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byKey(const Key('name-input')));
    expect(field.controller!.text, '12', reason: 'no C in the field');
    expect(field.decoration!.prefixText, 'C');
    await t.enterText(find.byKey(const Key('name-input')), '12A');
    await t.tap(find.byKey(const Key('name-ok')));
    await t.pumpAndSettle();
    expect(find.text('C012A'), findsOneWidget);
  });
}
