import 'package:anisched/src/models/holidays.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

final now = DateTime(2026, 11, 27, 14);

void main() {
  test('a day off wins over a holiday, a holiday over a rest weekday', () {
    final days = ChartDays(
      daysOff: [DaysOff(DateTime(2026, 11, 23), DateTime(2026, 11, 24))],
      holidays: {
        DateTime.utc(2026, 11, 23): '勤労感謝の日',
        DateTime.utc(2026, 11, 3): '文化の日',
      },
    );
    expect(days.kindOf(DateTime(2026, 11, 23)), DayKind.off); // a Monday
    expect(days.kindOf(DateTime(2026, 11, 24)), DayKind.off);
    expect(days.kindOf(DateTime(2026, 11, 3)), DayKind.holiday); // Tuesday
    expect(days.kindOf(DateTime(2026, 11, 29)), DayKind.rest); // Sunday
    expect(days.kindOf(DateTime(2026, 11, 25)), DayKind.plain);
    expect(days.holidayName(DateTime(2026, 11, 3, 18)), '文化の日');
    expect(days.holidayName(DateTime(2026, 11, 4)), isNull);
  });

  test('the three marks and today are four different colours', () {
    for (final c in [AppColors.light, AppColors.dark]) {
      final all = {c.restDay, c.dayOff, c.holiday, c.retake};
      expect(all, hasLength(4));
    }
  });

  testWidgets('a holiday on the header names itself', (t) async {
    final window = ChartWindow(DateTime(2026, 11, 1), 10);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SizedBox(
          width: 500,
          child: ChartHeader(
            window: window,
            today: now,
            days: ChartDays(holidays: {DateTime.utc(2026, 11, 3): '文化の日'}),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('holiday-2')), findsOneWidget);
    expect(find.byTooltip('文化の日'), findsOneWidget);
  });

  testWidgets('settings pick the holidays\' country and the two switches', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = sampleCatalogue(now);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.settings,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    Future<void> tap(String key) async {
      await t.ensureVisible(find.byKey(Key(key)));
      await t.pump();
      await t.tap(find.byKey(Key(key)));
      await t.pump();
    }

    await tap('holiday-KR');
    expect(store.settings.holidayCountry, HolidayCountry.korea);
    final shown = store.settings.showHolidays;
    await tap('holiday-show');
    expect(store.settings.showHolidays, !shown);
    final rest = store.settings.restOnHolidays;
    await tap('holiday-rest');
    expect(store.settings.restOnHolidays, !rest);
  });
}
