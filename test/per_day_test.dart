import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/fit_text.dart';
import 'package:anisched/src/ui/part_line.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

Pace pace({int remaining = 6, int workDays = 2, bool later = false}) => Pace(
  remaining: remaining,
  workDays: workDays,
  startsLater: later,
  end: now,
);

void main() {
  test('what today asks, as a short token', () {
    expect(perDayText(pace()), '3/day');
    expect(perDayText(pace(remaining: 5)), '2.5/day');
    expect(perDayText(pace(later: true)), '0/day', reason: 'not yet');
    expect(perDayText(pace(remaining: 0)), '', reason: 'nothing left');
    expect(perDayText(null), '');
  });

  for (final (size, shown) in const [
    (Size(1280, 800), true),
    (Size(800, 1280), true),
    (Size(390, 844), false),
  ]) {
    testWidgets(
      'the per-day column at $size: ${shown ? 'shown' : 'in the '
                'details only'}',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final store = sampleCatalogue(now);
        final reader = SyncCatalogueReader(store);
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AppShell(reader: reader, store: store, clock: () => now),
          ),
        );
        await t.pump();
        await t.pump();
        final cells = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('per-day-'),
        );
        if (!shown) {
          expect(cells, findsNothing);
          return;
        }
        expect(cells, findsWidgets);
        // The reader's own pace for each line, the same number.
        final signals = await reader.signals();
        for (final e in cells.evaluate()) {
          final key = (e.widget.key! as ValueKey<String>).value.substring(8);
          final want = perDayText(signals[key]?.pace);
          final fit = t.widget<FitText>(
            find.descendant(
              of: find.byWidget(e.widget),
              matching: find.byType(FitText),
            ),
          );
          expect(fit.span.toPlainText(), want, reason: key);
        }
      },
    );
  }
}
