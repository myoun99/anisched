import 'package:anisched/src/core/size_class.dart';
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

  testWidgets('days off are one colour, whatever their kind', (t) async {
    late Map<DayKind, Color> marks;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            marks = dayMarkColors(context);
            return const SizedBox();
          },
        ),
      ),
    );
    // Rest weekdays, the user's days off and holidays alike; plain days
    // have none (the bands only); today keeps its own red.
    expect(marks.values.toSet(), hasLength(1));
    expect(marks.containsKey(DayKind.plain), isFalse);
    expect(marks.values.first, isNot(AppColors.light.retake));
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
    // Its name on the ruler, under the day number.
    expect(find.byKey(const Key('ruler-2')), findsOneWidget);
    expect(find.text('文化の日'), findsOneWidget);
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

  testWidgets('a long press on the ruler makes a day off for everything', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    chartView.value = const ChartView();
    final store = sampleCatalogue(now);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          initialView: AppView.timeline,
          reader: SyncCatalogueReader(store),
          store: store,
          clock: () => now,
        ),
      ),
    );
    await t.pump();
    final restBefore = store.restDays().length;
    final ruler = find.byKey(const Key('ruler-press'));
    final box = t.getRect(ruler);
    final window = ChartWindow.of(now, SizeClass.wide, chartView.value);
    final dw = box.width / window.days;
    // The 3rd day of the window, on its ruler.
    await t.longPressAt(Offset(box.left + dw * 2.5, box.top + 10));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('event-title')), '여행');
    await t.tap(find.byKey(const Key('event-rest')));
    await t.pump();
    await t.tap(find.byKey(const Key('event-ok')));
    await t.pumpAndSettle();
    final rest = store.restDays();
    expect(rest, hasLength(restBefore + 1));
    final day = window.dayAt(2);
    final added = rest.firstWhere(
      (e) => e.date.month == day.month && e.date.day == day.day,
    );
    expect(added.title, '여행');
    expect(added.episodeId, isNull);
    // Shown on the ruler; a tap there opens it again.
    await t.tap(find.text('여행'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('event-delete')), findsOneWidget);
    expect(t.widget<Switch>(find.byKey(const Key('event-rest'))).value, isTrue);
  });
}
