import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:anisched/src/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  // The user's rule: toolbars speak in icons — no day counts, no item
  // counts, no 「오늘 2/3」; the words live in tooltips.
  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    for (final view in const [AppView.list, AppView.timeline, AppView.work]) {
      for (final month in [false, true]) {
        if (month && view == AppView.list) continue;
        testWidgets('no words in the ${view.name} toolbar '
            '${month ? '(months) ' : ''}at $size', (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          chartView.value = const ChartView();
          chartMonthView.value = month;
          addTearDown(() => chartMonthView.value = false);
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
          final bar = find.byType(ViewToolbar);
          expect(bar, findsOneWidget);
          expect(
            find.descendant(of: bar, matching: find.byType(Text)),
            findsNothing,
          );
          // Words drawn any other way (icons are glyphs of their font).
          expect(
            find.descendant(
              of: bar,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is RichText &&
                    w.text.style?.fontFamily != 'MaterialIcons' &&
                    w.text.toPlainText().trim().isNotEmpty,
              ),
            ),
            findsNothing,
          );
          expect(
            find.descendant(of: bar, matching: find.byType(Icon)),
            findsWidgets,
          );
        });
      }
    }
  }
}
