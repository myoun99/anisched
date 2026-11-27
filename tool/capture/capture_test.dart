// Screen captures for review on real fonts, not part of `flutter test`
// (it only runs test/). Run:
//   flutter test tool/capture/capture_test.dart
// PNGs land in build/captures/<scenario>-<size>.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/ui/shell.dart';
import 'package:anisched/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/sample_catalogue.dart';

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
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await family('MaterialIcons', [
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

typedef Scenario = Future<void> Function(WidgetTester t, Size size);

final scenarios = <String, (AppView, Scenario)>{
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
      final lines = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('line-'),
      );
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

  for (final MapEntry(key: name, value: (view, act)) in scenarios.entries) {
    for (final MapEntry(key: label, value: size) in sizes.entries) {
      testWidgets('$name $label', (t) async {
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final store = sampleCatalogue(now);
        final shot = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              scrollBehavior: const AlwaysScrollbarBehavior(),
              home: AppShell(
                initialView: view,
                reader: SyncCatalogueReader(store),
                store: store,
                clock: () => now,
              ),
            ),
          ),
        );
        await t.pump();
        await act(t, size);
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
