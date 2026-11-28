// The app's art from one mark, drawn by Flutter itself and written
// straight into every platform's folder (no copied pictures):
//   flutter test tool/app_art/render_app_art_test.dart
// Not part of `flutter test` (it runs test/ only). Previews land in
// build/app_art/. The mark is the ani series' (Anicel's constants): a bold
// ∧ on a 120 grid and, where the crossbar would be, Anisched's trademark
// — a short rounded bar, a day cell of a schedule (유저 2026-11-28: ②).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../capture/capture_test.dart' show loadFonts;

// ---- the mark (Anicel's grid) ----

const kGrid = 120.0;
const kAccent = Color(0xFF4F5BD5);
const kWhite = Color(0xFFFFFFFF);
const kCornerRadius = 27.0;
const kStroke = [Offset(30, 100), Offset(60, 24), Offset(90, 100)];
const kStrokeWidth = 22.0;

/// The trademark where the crossbar would be: a day cell.
const kCellCenter = Offset(60, 90);
const kCellSize = Size(18, 10);
const kCellRadius = 3.0;
const kLetterBounds = Rect.fromLTRB(19, 13, 101, 111);

/// macOS: the body's share of the canvas (Apple's template).
const kMacBody = 824 / 1024;

// The desktop start screen, in grid units: the letter (scaled) above
// the name, no ground; drawn tall for a 5K screen, the runner only
// scales it down.
const kSplashWidth = 240.0;
const kSplashHeight = 232.0;
const kSplashLetterScale = 1.3;
const kSplashNameSize = 34.0;
const kSplashGap = 12.0;
const kSplashShadow = Color(0x73000000);
const kSplashPictureHeight = 1440;

enum IconShape {
  /// Windows, Linux, Android legacy, web: the rounded square, transparent
  /// corners.
  rounded,

  /// iOS and web maskable: the ground to every edge, no transparency.
  fullBleed,

  /// macOS: the rounded body inset by Apple's margin.
  macTemplate,
}

/// Paints the letter and the cell (grid units) in [ink].
void paintLetter(Canvas c, Color ink, {MaskFilter? blur}) {
  final legs = Path()
    ..moveTo(kStroke[0].dx, kStroke[0].dy)
    ..lineTo(kStroke[1].dx, kStroke[1].dy)
    ..lineTo(kStroke[2].dx, kStroke[2].dy);
  c.drawPath(
    legs,
    Paint()
      ..color = ink
      ..maskFilter = blur
      ..style = PaintingStyle.stroke
      ..strokeWidth = kStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: kCellCenter,
        width: kCellSize.width,
        height: kCellSize.height,
      ),
      const Radius.circular(kCellRadius),
    ),
    Paint()
      ..color = ink
      ..maskFilter = blur,
  );
}

/// The icon at [size] px in [shape]; [letterScale] shrinks the letter
/// about the centre (maskable: inside the safe circle).
void paintIcon(
  Canvas c,
  double size,
  IconShape shape, {
  double letterScale = 1,
}) {
  c.save();
  switch (shape) {
    case IconShape.rounded:
      c.scale(size / kGrid);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, kGrid, kGrid),
          const Radius.circular(kCornerRadius),
        ),
        Paint()..color = kAccent,
      );
    case IconShape.fullBleed:
      c.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = kAccent);
      c.scale(size / kGrid);
    case IconShape.macTemplate:
      final body = size * kMacBody;
      c.translate((size - body) / 2, (size - body) / 2);
      c.scale(body / kGrid);
      final r = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, kGrid, kGrid),
        const Radius.circular(kCornerRadius),
      );
      c.drawRRect(
        r.shift(const Offset(0, 1.2)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      c.drawRRect(r, Paint()..color = kAccent);
  }
  if (letterScale != 1) {
    c.translate(kGrid / 2, kGrid / 2);
    c.scale(letterScale);
    c.translate(-kGrid / 2, -kGrid / 2);
  }
  paintLetter(c, kWhite);
  c.restore();
}

/// Android's adaptive foreground: the letter alone on 108 dp, the grid
/// as wide as the 72 dp the mask shows.
void paintAdaptiveForeground(Canvas c, double size) {
  c.save();
  final grid = size * 72 / 108;
  c.translate((size - grid) / 2, (size - grid) / 2);
  c.scale(grid / kGrid);
  paintLetter(c, kWhite);
  c.restore();
}

/// The start screen picture ([height] px tall): the letter in the accent
/// and the name in white under it, each with a soft shadow, no ground.
void paintSplash(Canvas c, double height) {
  final u = height / kSplashHeight;
  c.save();
  c.scale(u);
  const letter = kLetterBounds;
  final scaled = Size(
    letter.width * kSplashLetterScale,
    letter.height * kSplashLetterScale,
  );
  final name = TextPainter(
    text: const TextSpan(
      text: 'Anisched',
      style: TextStyle(
        fontFamily: 'NanumGothic',
        fontWeight: FontWeight.w700,
        fontSize: kSplashNameSize,
        color: kWhite,
        shadows: [
          Shadow(color: kSplashShadow, offset: Offset(0, 3), blurRadius: 5),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final total = scaled.height + kSplashGap + name.height;
  final top = (kSplashHeight - total) / 2;
  c.save();
  c.translate((kSplashWidth - scaled.width) / 2, top);
  c.scale(kSplashLetterScale);
  c.translate(-letter.left, -letter.top);
  // The shadow (offset 0,3 · sigma 5, in grid units), then the letter.
  c.save();
  c.translate(0, 3 / kSplashLetterScale);
  paintLetter(
    c,
    kSplashShadow,
    blur: const MaskFilter.blur(BlurStyle.normal, 5 / kSplashLetterScale),
  );
  c.restore();
  paintLetter(c, kAccent);
  c.restore();
  name.paint(
    c,
    Offset((kSplashWidth - name.width) / 2, top + scaled.height + kSplashGap),
  );
  name.dispose();
  c.restore();
}

// ---- writing ----

Future<Uint8List> render(
  WidgetTester t,
  int w,
  int h,
  void Function(Canvas c) draw,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final pic = rec.endRecording();
  final bytes = await t.runAsync(() async {
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  });
  pic.dispose();
  return bytes!;
}

void write(String path, List<int> bytes) => File(path)
  ..createSync(recursive: true)
  ..writeAsBytesSync(bytes);

/// A PNG's width and height (its IHDR).
(int, int) pngSize(String path) {
  final d = ByteData.sublistView(File(path).readAsBytesSync());
  return (d.getUint32(16), d.getUint32(20));
}

/// An .ico of PNG images (Windows Vista on reads them).
Uint8List ico(List<(int, Uint8List)> images) {
  final out = BytesBuilder();
  final head = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  out.add(head.buffer.asUint8List());
  var offset = 6 + 16 * images.length;
  for (final (size, png) in images) {
    final e = ByteData(16)
      ..setUint8(0, size >= 256 ? 0 : size)
      ..setUint8(1, size >= 256 ? 0 : size)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(e.buffer.asUint8List());
    offset += png.length;
  }
  for (final (_, png) in images) {
    out.add(png);
  }
  return out.toBytes();
}

const _note = '<!-- Written by tool/app_art/render_app_art_test.dart. -->';

void main() {
  setUpAll(loadFonts);

  Future<Uint8List> icon(
    WidgetTester t,
    int s,
    IconShape shape, {
    double letterScale = 1,
  }) => render(
    t,
    s,
    s,
    (c) => paintIcon(c, s * 1.0, shape, letterScale: letterScale),
  );

  Future<Uint8List> foreground(WidgetTester t, int s) =>
      render(t, s, s, (c) => paintAdaptiveForeground(c, s * 1.0));

  testWidgets('every platform', (t) async {
    // iOS: every size the icon set holds, full bleed (no transparency).
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final f in Directory(ios).listSync().whereType<File>()) {
      if (!f.path.endsWith('.png')) continue;
      final (w, _) = pngSize(f.path);
      write(f.path, await icon(t, w, IconShape.fullBleed));
    }
    // macOS: Apple's template.
    const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final f in Directory(mac).listSync().whereType<File>()) {
      if (!f.path.endsWith('.png')) continue;
      final (w, _) = pngSize(f.path);
      write(f.path, await icon(t, w, IconShape.macTemplate));
    }
    // Android: the legacy rounded square, and the adaptive pair.
    const res = 'android/app/src/main/res';
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    for (final MapEntry(key: d, value: x) in densities.entries) {
      write(
        '$res/mipmap-$d/ic_launcher.png',
        await icon(t, (48 * x).round(), IconShape.rounded),
      );
      write(
        '$res/mipmap-$d/ic_launcher_foreground.png',
        await foreground(t, (108 * x).round()),
      );
    }
    write(
      '$res/mipmap-anydpi-v26/ic_launcher.xml',
      '''
<?xml version="1.0" encoding="utf-8"?>
$_note
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''
          .trimLeft()
          .codeUnits,
    );
    write(
      '$res/values/ic_launcher_background.xml',
      '''
<?xml version="1.0" encoding="utf-8"?>
$_note
<resources>
    <color name="ic_launcher_background">#4F5BD5</color>
</resources>
'''
          .trimLeft()
          .codeUnits,
    );
    // Windows: one .ico of every size the shell asks for.
    write(
      'windows/runner/resources/app_icon.ico',
      ico([
        for (final s in [16, 20, 24, 32, 40, 48, 64, 96, 128, 256])
          (s, await icon(t, s, IconShape.rounded)),
      ]),
    );
    // Linux: the window's icon.
    write(
      'linux/runner/resources/app_icon.png',
      await icon(t, 256, IconShape.rounded),
    );
    // Web: the favicon, the app icons, the maskable ones.
    write('web/favicon.png', await icon(t, 32, IconShape.rounded));
    for (final s in [192, 512]) {
      write('web/icons/Icon-$s.png', await icon(t, s, IconShape.rounded));
      write(
        'web/icons/Icon-maskable-$s.png',
        await icon(t, s, IconShape.fullBleed, letterScale: 0.72),
      );
    }
    // Every desktop's start screen, from the app's assets.
    const h = kSplashPictureHeight;
    final w = (h * kSplashWidth / kSplashHeight).round();
    write(
      'assets/app_art/splash.png',
      await render(t, w, h, (c) => paintSplash(c, h * 1.0)),
    );
  });

  testWidgets('previews', (t) async {
    for (final s in [1024, 64, 32, 16]) {
      write('build/app_art/icon-$s.png', await icon(t, s, IconShape.rounded));
    }
    write(
      'build/app_art/ios-1024.png',
      await icon(t, 1024, IconShape.fullBleed),
    );
    write(
      'build/app_art/mac-1024.png',
      await icon(t, 1024, IconShape.macTemplate),
    );
    write('build/app_art/android-foreground-432.png', await foreground(t, 432));
    write(
      'build/app_art/maskable-512.png',
      await icon(t, 512, IconShape.fullBleed, letterScale: 0.72),
    );
    // The start screen as it shows: half the short side of a 1280×800
    // screen, on a desktop.
    await t.runAsync(() async {});
    write(
      'build/app_art/splash-desktop.png',
      await render(t, 1280, 800, (c) {
        c.drawRect(
          const Rect.fromLTWH(0, 0, 1280, 800),
          Paint()
            ..shader = ui.Gradient.radial(const Offset(640, 400), 900, [
              const Color(0xFF3A4660),
              const Color(0xFF1A1D26),
            ]),
        );
        const h = 400.0;
        const w = h * kSplashWidth / kSplashHeight;
        c.translate((1280 - w) / 2, (800 - h) / 2);
        paintSplash(c, h);
      }),
    );
  });
}
