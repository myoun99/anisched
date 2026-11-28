// Screen captures for review on real fonts, not part of `flutter test`
// (it only runs test/). Run:
//   flutter test tool/capture/capture_test.dart
// PNGs land in build/captures/<scenario>-<size>.png. CAPTURE=a,b limits
// the run to those scenarios (light and dark).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/device_settings.dart';
import 'package:anisched/src/services/document_rows.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/document_trouble.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:anisched/src/ui/hold.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/text/strings.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:anisched/src/ui/views/stats_view.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart' hide UndoHistory;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/sample_catalogue.dart';
import 'rich_stats.dart';

final now = DateTime(2026, 11, 27, 14);

const sizes = {
  'phone-portrait': Size(390, 844),
  'phone-landscape': Size(844, 390),
  'tablet-portrait': Size(800, 1280),
  'tablet-landscape': Size(1280, 800),
};

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('BIZUDPGothic', [
    'assets/fonts/BIZUDPGothic-Regular.ttf',
    'assets/fonts/BIZUDPGothic-Bold.ttf',
  ]);
  await family('NanumGothic', [
    'assets/fonts/NanumGothic-Regular.ttf',
    'assets/fonts/NanumGothic-Bold.ttf',
  ]);
  await family('NotoSansSC', [
    'assets/fonts/NotoSansSC-Regular.otf',
    'assets/fonts/NotoSansSC-Bold.otf',
  ]);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await family('MaterialIcons', [
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Widgets whose string key starts with [prefix] (`line-`, `cut-` …).
Finder byKeyPrefix(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

typedef Scenario = Future<void> Function(WidgetTester t, Size size);

final scenarios = <String, (AppView, Scenario)>{
  // Round 2: an opened line (cuts folded, D label is a button) and a cut
  // on the time bar, paused.
  'details-open': (
    AppView.list,
    (t, size) async {
      final lines = byKeyPrefix('line-');
      await t.tap(lines.at(0));
      await t.pump();
      final fold = byKeyPrefix('fold-cuts-');
      await t.tap(fold.first);
      await t.pump();
      final chip = byKeyPrefix('cut-');
      if (chip.evaluate().isNotEmpty) {
        await t.tap(chip.first);
        await t.pump();
      }
      await t.tap(fold.first);
      await t.pump();
    },
  ),
  'settings': (AppView.settings, (t, size) async {}),
  'timeline': (AppView.timeline, (t, size) async {}),
  // Mid-drag: the days slid by part of a day, bars cut at the edges.
  'timeline-slide': (
    AppView.timeline,
    (t, size) async {
      chartView.value = chartView.value.scrolled(2.45);
      await t.pump();
    },
  ),

  // A bundle's row (LO and 原画 of one part): both bars on it, named.
  'bundle-timeline': (AppView.timeline, (t, size) async {}),
  // Zoomed all the way out: the grips stay 16 px, outside short bars.
  'bundle-timeline-zoomout': (
    AppView.timeline,
    (t, size) async {
      chartView.value = const ChartView(days: ChartView.maxDays);
      await t.pump();
    },
  ),

  // Round 3: the date area zoomed out two steps and scrolled a week on.
  'timeline-zoom': (
    AppView.timeline,
    (t, size) async {
      // Two steps out on the zoom, a week on.
      await t.drag(
        find.byKey(const Key('chart-zoom')),
        const Offset(-ZoomDrag.stepPixels * 2 - 4, 0),
      );
      await t.pump();
      chartView.value = chartView.value.scrolled(7);
      await t.pump();
    },
  ),
  'work-zoom': (
    AppView.work,
    (t, size) async {
      await t.drag(
        find.byKey(const Key('chart-zoom')),
        const Offset(ZoomDrag.stepPixels + 4, 0),
      );
      await t.pump();
    },
  ),
  // Round 4: holds and deadline rounds — the first line opened with its
  // rounds unfolded; another part on hold; one cut held on its own.
  'holds': (
    AppView.list,
    (t, size) async {
      Folds.dueRounds.value = true;
      Folds.cutsInDetails.value = true;
      final lines = byKeyPrefix('line-');
      final extended = find.ancestor(
        of: find.byWidgetPredicate((w) => w is RoundBadge && w.revision == 2),
        matching: lines,
      );
      await t.tap(extended.first);
      await t.pump();
      await t.pump();
    },
  ),
  // Round 5: one cut pulled (引き上げ), shown through the filter, its
  // line opened; then two lines picked to show the bar's 빠짐 button.
  'dropped': (
    AppView.list,
    (t, size) async {
      Folds.cutsInDetails.value = true;
      await t.tap(find.byKey(const Key('filter-button')));
      await t.pump();
      await t.tap(find.text('빠진 것도 보기'));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final lines = byKeyPrefix('line-');
      await t.tap(lines.at(1));
      await t.pump();
      await t.longPress(lines.at(0));
      await t.pump();
    },
  ),
  // Round 7: a timeline row opened (the list's details, board-wide).
  'timeline-open': (
    AppView.timeline,
    (t, size) async {
      await t.tap(byKeyPrefix('tl-label-').at(1));
      await t.pump();
      await t.pump();
    },
  ),
  // Round 7: a cut on the time bar, its picker open (this cut centred).
  'timer-pick': (
    AppView.list,
    (t, size) async {
      Folds.cutsInDetails.value = true;
      await t.tap(byKeyPrefix('line-').at(1));
      await t.pump();
      await t.tap(byKeyPrefix('cut-').at(1));
      await t.pump();
      await t.tap(find.byKey(const Key('timer-cut')));
      await t.pump();
      await t.pump();
      await t.pump();
    },
  ),
  // Round 8: the same cuts at two stages, one line (「LO・原画」).
  'bundle': (AppView.list, (t, size) async {}),
  // …opened: its stages, the first one opened too.
  'bundle-open': (
    AppView.list,
    (t, size) async {
      final bundle = byKeyPrefix('line-bundle:').first;
      await t.ensureVisible(bundle);
      await t.pump();
      await t.tap(bundle);
      await t.pump();
      final id = (t.widget(bundle).key! as ValueKey<String>).value.split(
        ':',
      )[2];
      final stage = byKeyPrefix('line-part:$id:').last;
      await t.ensureVisible(stage);
      await t.pump();
      await t.tap(stage);
      await t.pump();
      await t.pump();
    },
  ),
  // Round 8: a work bar tapped open, its panel beside the board.
  'work-open': (
    AppView.work,
    (t, size) async {
      await t.tap(byKeyPrefix('work-open-').at(1), warnIfMissed: false);
      await t.pump();
      await t.pump();
      await t.pump();
    },
  ),
  // Round 9: clients on works; bars in their stage's colour.
  'r9-list': (AppView.list, (t, size) async {}),
  'r9-timeline': (AppView.timeline, (t, size) async {}),
  'r9-timeline-open': (
    AppView.timeline,
    (t, size) async {
      await t.tap(byKeyPrefix('tl-label-').at(1));
      await t.pump();
      await t.pump();
    },
  ),
  'r9-work-open': (
    AppView.work,
    (t, size) async {
      await t.tap(byKeyPrefix('work-open-').at(0), warnIfMissed: false);
      await t.pump();
      await t.pump();
    },
  ),
  // Round 10: rest weekdays (blue), a day off (orange), a holiday
  // (purple: 11/23) and today (red) on the chart backgrounds; one-day
  // bars at half-day grips; nothing picked (no actions).
  'r10-timeline': (AppView.timeline, (t, size) async {}),
  'r10-work': (AppView.work, (t, size) async {}),
  'r10-list': (AppView.list, (t, size) async {}),
  // Round 10: the month view — each month a band, the next under it.
  'r10-month-timeline': (
    AppView.timeline,
    (t, size) async {
      chartMonthView.value = true;
      await t.pump();
      await t.pump();
    },
  ),
  'r10-month-work': (
    AppView.work,
    (t, size) async {
      chartMonthView.value = true;
      await t.pump();
      await t.pump();
    },
  ),
  'r10-settings': (
    AppView.settings,
    (t, size) async {
      await t.ensureVisible(find.byKey(const Key('holiday-JP')));
      await t.pump();
    },
  ),
  // Round 7: the register screen's top (how many rows the roles take).
  'register-top': (AppView.register, (t, size) async {}),
  // Round 4: the statistics tab, loaded.
  'stats': (
    AppView.stats,
    (t, size) async {
      await t.pump();
      await t.pump();
    },
  ),
  // Round 3: each language on the list and the settings.
  for (final l in Lang.values)
    if (l != Lang.ko) ...{
      'list-${l.name}': (AppView.list, (t, size) async => appLang.value = l),
      'settings-${l.name}': (
        AppView.settings,
        (t, size) async => appLang.value = l,
      ),
    },

  // ① The filter popover, open over the list.
  'filter-open': (
    AppView.list,
    (t, size) async {
      await t.tap(find.byKey(const Key('filter-button')));
      await t.pump();
    },
  ),
  // ② The list with two units picked: the picked-task bar in its place.
  'two-picked': (
    AppView.list,
    (t, size) async {
      final lines = byKeyPrefix('line-');
      await t.longPress(lines.at(0));
      await t.pump();
      await t.longPress(lines.at(1));
      await t.pump();
    },
  ),
  // The same two picked, the ⋯ menu open where the bar is short of room.
  'picked-more': (
    AppView.list,
    (t, size) async {
      final lines = byKeyPrefix('line-');
      await t.longPress(lines.at(0));
      await t.pump();
      await t.longPress(lines.at(1));
      await t.pump();
      final more = find.byKey(const Key('pick-more'));
      if (more.evaluate().isNotEmpty) {
        await t.tap(more);
        await t.pump();
      }
    },
  ),
  // The delete confirmation over the list, one line picked.
  'delete-confirm': (
    AppView.list,
    (t, size) async {
      await t.longPress(byKeyPrefix('line-').at(1));
      await t.pump();
      if (find.byKey(const Key('pick-delete')).evaluate().isEmpty) {
        await t.tap(find.byKey(const Key('pick-more')));
        await t.pump();
      }
      await t.tap(find.byKey(const Key('pick-delete')));
      await t.pump();
    },
  ),
  // A document that would not open: one line, details opened.
  'doc-trouble': (
    AppView.list,
    (t, size) async {
      final context = t.element(find.byType(AppShell));
      unawaited(
        showDocumentTrouble(
          context,
          NotADocumentException('일정.anisched', 'not an Anisched document'),
          retry: () async {},
        ),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('doc-trouble-details')));
      await t.pump();
    },
  ),
  // Archived work shown by the filter (one card put away), faded.
  'archived-shown': (
    AppView.list,
    (t, size) async {
      await t.tap(find.byKey(const Key('filter-button')));
      await t.pump();
      await t.tap(find.byKey(const Key('filter-archived')));
      await t.pump();
      await t.pump();
    },
  ),
  // The edit dialog for one picked bundle.
  'bundle-edit': (
    AppView.list,
    (t, size) async {
      await t.longPress(byKeyPrefix('line-').at(1));
      await t.pump();
      if (find.byKey(const Key('pick-edit')).evaluate().isEmpty) {
        await t.tap(find.byKey(const Key('pick-more')));
        await t.pump();
      }
      await t.tap(find.byKey(const Key('pick-edit')));
      await t.pump();
      await t.pump();
    },
  ),
  // An opened unit's 「+」 and the add-cuts dialog, count 3.
  'add-cuts': (
    AppView.list,
    (t, size) async {
      Folds.cutsInDetails.value = true;
      await t.tap(byKeyPrefix('line-').at(1));
      await t.pump();
      final add = byKeyPrefix('cut-add-').first;
      await Scrollable.ensureVisible(t.element(add), alignment: 0.5);
      await t.pump();
      await t.tap(add);
      await t.pump();
      await t.enterText(find.byKey(const Key('add-count')), '3');
      await t.pump();
    },
  ),
  // The client list open: each line's colour, rename and delete.
  'presets': (
    AppView.register,
    (t, size) async {
      await t.tap(find.byKey(const Key('pick-client')));
      await t.pump();
      await t.pump();
    },
  ),
  // Every ruler row on: year, month, days, weekdays, events.
  'ruler-all': (
    AppView.timeline,
    (t, size) async {
      rulerRows[RulerTab.timeline]!.value = (
        year: true,
        month: true,
        weekday: true,
      );
      await t.pump();
    },
  ),
  // The ruler rows' menu open.
  'ruler-menu': (
    AppView.timeline,
    (t, size) async {
      await t.tap(find.byKey(const Key('ruler-rows')));
      await t.pump();
      await t.pump();
    },
  ),
  // The month view: each band's month in its corner.
  'month-corner': (
    AppView.timeline,
    (t, size) async {
      chartMonthView.value = true;
      await t.pump();
    },
  ),
  // The stats' detail table, the first client opened down to a cut.
  'stats-table': (
    AppView.stats,
    (t, size) async {
      statsAsTable.value = true;
      await t.pump();
      await t.pump();
      for (var depth = 0; depth < 5; depth++) {
        final rows = byKeyPrefix('stats-row-');
        if (rows.evaluate().length <= depth) break;
        await t.tap(rows.at(depth));
        await t.pump();
      }
    },
  ),
  // ③ The register screen's cut grid with its margins.
  'register-grid': (
    AppView.register,
    (t, size) async {
      await t.tap(find.byKey(const Key('pick-work')));
      await t.pumpAndSettle();
      await t.tap(find.text('별빛 정류장').last);
      await t.pumpAndSettle();
      final grid = find.byKey(const Key('cell-C001'));
      await t.scrollUntilVisible(
        grid,
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.drag(find.byType(CustomScrollView), const Offset(0, -60));
      await t.pump();
      await t.tap(grid);
      await t.tap(find.byKey(const Key('cell-C002')));
      await t.pump();
    },
  ),
};

void main() {
  final out = Directory('build/captures')..createSync(recursive: true);
  setUpAll(loadFonts);
  final only = Platform.environment['CAPTURE']?.split(',').toSet();

  // Round 8: bars drawn 4× on the chart (today's column included): grips
  // 〈 〉 at the ends, the label between them; short bars by proposal.
  for (final days in [8, 16]) {
    for (final dark in [false, true]) {
      final name = 'bar-zoom-$days${dark ? '-dark' : ''}';
      if (only != null && !only.contains('bar-zoom')) continue;
      testWidgets(name, (t) async {
        const size = Size(420, 300);
        t.view.physicalSize = size * 4;
        t.view.devicePixelRatio = 4;
        addTearDown(t.view.reset);
        final shot = GlobalKey();
        final window = ChartWindow(DateTime(2026, 11, 20), days);
        // (days, opened)
        const rows = [
          (1, true),
          (1, false),
          (2, false),
          (3, false),
          (6, false),
        ];
        await t.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: ChartBoard(
                    window: FixedWindow(window),
                    today: DateTime(2026, 11, 21, 14),
                    days: const ChartDays(),
                    labelWidth: 56,
                    rowCount: rows.length,
                    label: (context, r) => Center(
                      child: Text(
                        '${rows[r].$1}d${rows[r].$2 ? ' ●' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    bars: (context, r, window) => [
                      ChartBar(
                        window: window,
                        start: DateTime(2026, 11, 21),
                        end: DateTime(2026, 11, 20 + rows[r].$1),
                        color: Theme.of(context).colorScheme.primary,
                        textColor: Colors.white,
                        label: '별빛 정류장 #07 · 원화 · 4 cut',
                        onDates: (a, b) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        final boundary =
            shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 4);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${out.path}/$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      });
    }
  }

  for (final dark in [false, true]) {
    for (final MapEntry(key: base, value: (view, act)) in scenarios.entries) {
      if (only != null && !only.contains(base)) continue;
      final name = dark ? '$base-dark' : base;
      for (final MapEntry(key: label, value: size) in sizes.entries) {
        testWidgets('$name $label', (t) async {
          Folds.cutsInDetails.value = false;
          chartMonthView.value = false;
          statsAsTable.value = false;
          for (final r in rulerRows.values) {
            r.value = defaultRulerRows;
          }
          Folds.dueRounds.value = false;
          chartView.value = const ChartView();
          chartMonthView.value = false;
          appLang.value = Lang.ko;
          addTearDown(() => appLang.value = Lang.ko);
          // A scenario that only switches the language does so up front.
          final langOnly =
              base.contains('-') &&
              Lang.values.any((l) => base.endsWith('-${l.name}'));
          if (langOnly) await act(t, size);
          t.view.physicalSize = size * 2;
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          final store = sampleCatalogue(now);
          // As the app runs: every write can be undone (↶ ↷ shown).
          UndoHistory.attach(store.db);
          if (base == 'holds') prepareHolds(store);
          if (base == 'archived-shown') {
            final g = store.partGroups()[1];
            store.archiveTasks([for (final x in g.tasks) x.id]);
          }
          if (base.startsWith('bundle')) prepareBundles(store);
          if (base.startsWith('r9')) prepareClients(store);
          if (base.startsWith('r10')) {
            // A day off of the user's own next week; Japan's holidays.
            store.addRestDays(
              DateTime(2026, 12, 1),
              end: DateTime(2026, 12, 2),
              title: '여행',
            );
            // A note of no episode on the ruler.
            store.addEvent(date: DateTime(2026, 11, 30), title: '회의');
          }
          if (base == 'dropped') {
            final g = store.partGroups().where((g) => g.tasks.length > 2);
            store.handOff([g.elementAt(1).tasks.first.id]);
          }
          // Real shadows (tests draw them as solid outlines by default).
          debugDisableShadows = false;
          final shot = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: shot,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: appLang.value.locale,
                supportedLocales: [for (final l in Lang.values) l.locale],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                scrollBehavior: const AlwaysScrollbarBehavior(),
                home: AppShell(
                  initialView: view,
                  reader: base.startsWith('stats')
                      ? RichStatsReader(store, now)
                      : SyncCatalogueReader(store),
                  store: store,
                  timer: WorkTimerStore(store.db, clock: () => now),
                  clock: () => now,
                ),
              ),
            ),
          );
          await t.pump();
          if (!langOnly) await act(t, size);
          await t.pump(const Duration(milliseconds: 500));
          final boundary =
              shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('${out.path}/$name-$label.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
          });
          debugDisableShadows = true;
        });
      }
    }
  }
}

/// Two rounds on one part, a part on hold, one cut held on its own.
void prepareHolds(CatalogueStore store) {
  final parts = [
    for (final g in store.partGroups())
      if (g.kind == GroupKind.part) g,
  ];
  final a = parts[1];
  store.extendDue(
    DueTarget.part(a.partId!, a.stageId),
    a.dueAt!.add(const Duration(days: 3)),
  );
  final b = parts[2];
  store.setPartWaiting(
    b.partId!,
    b.stageId,
    waiting: true,
    reason: 'LO 待ち',
    until: now.add(const Duration(days: 4)),
  );
  store.setTaskWaiting(a.tasks.last.id, waiting: true, reason: '修正待ち');
}

/// 별빛 #07 parts B and C get 原画 after their LO: two bundles.
void prepareBundles(CatalogueStore store) {
  final lo = [
    for (final g in store.partGroups())
      if (g.workTitle == '별빛 정류장' && g.stageName == 'LO') g,
  ];
  for (final (i, g) in lo.indexed) {
    // LO from a week back, so its bar shows beside 原画's.
    store.setPartKickoff(
      g.partId!,
      g.stageId,
      DateTime(now.year, now.month, now.day - 8),
    );
    final genga = store.stages(g.workId).firstWhere((s) => s.name == '원화').id;
    store.addTasksForPart(g.partId!, genga);
    store.setPartDue(
      g.partId!,
      genga,
      DateTime(now.year, now.month, now.day + 5 + i * 4, 23, 59),
    );
  }
}

/// Clients on three of the works (round 9's chips) and two events on
/// 별빛 #07: one on its bars, one past them.
void prepareClients(CatalogueStore store) {
  final a = store.addClient('스튜디오 아침', color: 0xFFE0843B);
  final b = store.addClient('Studio Kumo', color: 0xFF2E9E6B);
  final groups = store.partGroups();
  final works = {for (final g in groups) g.workTitle: g.workId};
  store.setWorkClient(works['별빛 정류장']!, a);
  store.setWorkClient(works['마법소녀 리코']!, b);
  store.setWorkClient(works['여름 끝에서']!, a);
  final star = groups.firstWhere((g) => g.workTitle == '별빛 정류장');
  store.addEvent(
    episodeId: star.episodeId,
    date: now.add(const Duration(days: 2)),
    timeMinutes: 13 * 60,
    title: 'アフレコ',
  );
  store.addEvent(
    episodeId: star.episodeId,
    date: now.add(const Duration(days: 9)),
    title: '打ち合わせ',
    note: '스튜디오 B',
  );
}
