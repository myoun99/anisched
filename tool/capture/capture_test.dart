// Screen captures for review on real fonts, not part of `flutter test`
// (it only runs test/). Run:
//   flutter test tool/capture/capture_test.dart
// PNGs land in build/captures/<scenario>-<size>.png. CAPTURE=a,b limits
// the run to those scenarios (light and dark).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:anisched/src/ui/fold.dart';
import 'package:anisched/src/ui/hold.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/text/strings.dart';
import 'package:anisched/src/ui/views/chart.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
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
  for (final dark in [false, true]) {
    for (final MapEntry(key: base, value: (view, act)) in scenarios.entries) {
      if (only != null && !only.contains(base)) continue;
      final name = dark ? '$base-dark' : base;
      for (final MapEntry(key: label, value: size) in sizes.entries) {
        testWidgets('$name $label', (t) async {
          Folds.cutsInDetails.value = false;
          Folds.dueRounds.value = false;
          chartView.value = const ChartView();
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
          if (base == 'holds') prepareHolds(store);
          if (base == 'dropped') {
            final g = store.partGroups().where((g) => g.tasks.length > 2);
            store.handOff([g.elementAt(1).tasks.first.id]);
          }
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
