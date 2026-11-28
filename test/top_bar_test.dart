import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  for (final size in const [
    Size(390, 844),
    Size(844, 390),
    Size(800, 1280),
    Size(1280, 800),
  ]) {
    testWidgets('the picked-task tools end at the right margin ($size)', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = sampleCatalogue(now);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            reader: SyncCatalogueReader(store),
            store: store,
            clock: () => now,
          ),
        ),
      );
      await t.pump();
      await t.longPress(
        find.byWidgetPredicate((w) => '${w.key}'.startsWith("[<'line-")).first,
      );
      await t.pump();
      // The bar's side padding is 14: ✕ sits against it.
      expect(
        t.getTopRight(find.byKey(const Key('pick-clear'))).dx,
        size.width - 14,
      );
      // The count and actions run leftwards from there, past the app name.
      final name = t.getTopRight(find.text('Anisched'));
      expect(
        t.getTopLeft(find.byKey(const Key('top-tools'))).dx,
        greaterThan(name.dx),
      );
    });
  }

  for (final view in [
    AppView.list,
    AppView.timeline,
    AppView.work,
    AppView.stats,
  ]) {
    testWidgets('${view.name}: the toolbar sits at the right end', (t) async {
      const size = Size(1280, 800);
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
      await t.pump();
      final bar = find.byKey(const Key('view-toolbar'));
      final wrap = t.renderObject<RenderBox>(bar);
      var right = 0.0;
      var left = double.infinity;
      wrap.visitChildren((child) {
        final box = child as RenderBox;
        final x = box.localToGlobal(Offset.zero).dx;
        if (x + box.size.width > right) right = x + box.size.width;
        if (x < left) left = x;
      });
      // Its side padding is 12: the last control ends against it.
      expect(right, closeTo(size.width - 12, 0.5));
      expect(left, greaterThan(size.width / 2), reason: 'not on the left');
      // The charts say what they are drawn by, on the left.
      final basis = switch (view) {
        AppView.timeline => '스케줄',
        AppView.work => '작업 예상',
        _ => null,
      };
      final label = find.byKey(const Key('toolbar-basis'));
      if (basis == null) {
        expect(label, findsNothing);
      } else {
        expect(
          find.descendant(of: label, matching: find.text(basis)),
          findsOneWidget,
        );
        expect(t.getTopLeft(label).dx, lessThan(size.width / 4));
      }
    });
  }
}
