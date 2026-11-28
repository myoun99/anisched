// The app's art from one mark: every size of the icon, a phone home
// screen and the desktop start screen, drawn by Flutter itself. Not part
// of `flutter test` (it runs test/ only). Run:
//   flutter test tool/app_art/render_app_art_test.dart
// PNGs land in build/app_art/<proposal>/. Step 1 (유저 2026-11-28):
// proposals only — no platform file is written until one is picked.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../capture/capture_test.dart' show loadFonts;

/// The ani series' mark on a 120 grid: a bold ∧ (no crossbar, round
/// ends) and, where the crossbar would be, a dot — the trademark.
class Mark {
  const Mark({
    required this.name,
    required this.ground,
    this.ink = Colors.white,
    this.dot,
    this.dotShape = DotShape.round,
    this.lines = false,
  });

  final String name;

  /// The rounded square's colour.
  final Color ground;

  /// The ∧'s colour (white on the ground; the ground's on the start
  /// screen, where there is no ground).
  final Color ink;

  /// The dot's colour when it is not the ink's.
  final Color? dot;
  final DotShape dotShape;

  /// Faint timeline rows across the ground.
  final bool lines;

  static const grid = 120.0;
  static const radius = 27.0;
  static const stroke = 22.0;
  static const apex = Offset(60, 26);
  static const feet = (Offset(28, 94), Offset(92, 94));
  static const dotAt = Offset(60, 78);
  static const dotRadius = 8.5;

  /// Paints the mark into [size] (a square). [ground] false: the ∧ and
  /// the dot alone, in the ground's colour (the start screen).
  void paint(Canvas canvas, double size, {bool ground = true}) {
    canvas.save();
    canvas.scale(size / grid);
    if (ground) {
      final r = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, grid, grid),
        const Radius.circular(radius),
      );
      canvas.drawRRect(r, Paint()..color = this.ground);
      if (lines) {
        canvas.save();
        canvas.clipRRect(r);
        final faint = Paint()..color = Colors.white.withValues(alpha: 0.10);
        for (final y in [22.0, 46.0, 70.0, 94.0]) {
          canvas.drawRect(Rect.fromLTWH(0, y, grid, 1.4), faint);
        }
        // One bar on a row, as on the timeline.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(70, 100, 38, 8),
            const Radius.circular(4),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.16),
        );
        canvas.restore();
      }
    }
    final ink = ground ? this.ink : this.ground;
    final legs = Path()
      ..moveTo(feet.$1.dx, feet.$1.dy)
      ..lineTo(apex.dx, apex.dy)
      ..lineTo(feet.$2.dx, feet.$2.dy);
    canvas.drawPath(
      legs,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dotPaint = Paint()..color = dot ?? ink;
    switch (dotShape) {
      case DotShape.round:
        canvas.drawCircle(dotAt, dotRadius, dotPaint);
      case DotShape.cell:
        // A day cell of the schedule: a short rounded bar.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: dotAt, width: 18, height: 10),
            const Radius.circular(3),
          ),
          dotPaint,
        );
    }
    canvas.restore();
  }
}

enum DotShape { round, cell }

/// Anisched's accent (the app's theme primary, light).
const accent = Color(0xFF4F5BD5);

const proposals = [
  // ① Anicel's mark as it is; only the colour tells them apart.
  Mark(name: '1-accent', ground: accent),
  // ② The dot becomes a day cell of a schedule.
  Mark(name: '2-cell', ground: accent, dotShape: DotShape.cell),
  // ③ The dot kept; faint timeline rows behind.
  Mark(name: '3-lines', ground: accent, lines: true),
  // ④ The dot in a warm colour of its own (today's red, softened): the
  // trademark still reads at 16 px.
  Mark(name: '4-warm-dot', ground: accent, dot: Color(0xFFFF8A65)),
];

Future<void> save(
  WidgetTester t,
  String path,
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
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
  pic.dispose();
}

TextPainter label(String text, double size, Color color, {bool bold = false}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'NanumGothic',
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

void main() {
  setUpAll(loadFonts);
  const out = 'build/app_art';

  for (final m in proposals) {
    testWidgets('render ${m.name}', (t) async {
      final dir = '$out/${m.name}';
      // The icon at its sizes, each drawn at its own size.
      for (final s in [1024, 64, 32, 16]) {
        await save(t, '$dir/icon-$s.png', s, s, (c) => m.paint(c, s * 1.0));
      }

      // A phone's home screen: the icon among others, its name under it.
      const pw = 720.0;
      const ph = 560.0;
      await save(t, '$dir/home.png', pw.toInt(), ph.toInt(), (c) {
        c.drawRect(
          const Rect.fromLTWH(0, 0, pw, ph),
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, ph), [
              const Color(0xFF2B3A55),
              const Color(0xFF6B7FA8),
            ]),
        );
        const icon = 120.0;
        const gap = 52.0;
        const left = (pw - 4 * icon - 3 * gap) / 2;
        final others = [
          const Color(0xFFE8E8E8),
          const Color(0xFF34A853),
          const Color(0xFFFBBC05),
          const Color(0xFF9AA0A6),
          const Color(0xFFEA4335),
          const Color(0xFF1A73E8),
          const Color(0xFFF6F6F6),
        ];
        var k = 0;
        for (var row = 0; row < 2; row++) {
          for (var col = 0; col < 4; col++) {
            final x = left + col * (icon + gap);
            final y = 70.0 + row * (icon + 90);
            c.save();
            c.translate(x, y);
            if (row == 0 && col == 1) {
              m.paint(c, icon);
            } else {
              c.drawRRect(
                RRect.fromRectAndRadius(
                  const Rect.fromLTWH(0, 0, icon, icon),
                  const Radius.circular(icon * Mark.radius / Mark.grid),
                ),
                Paint()..color = others[k++ % others.length],
              );
            }
            c.restore();
            final name = row == 0 && col == 1 ? 'Anisched' : '';
            if (name.isNotEmpty) {
              final p = label(name, 24, Colors.white);
              p.paint(c, Offset(x + (icon - p.width) / 2, y + icon + 12));
            }
          }
        }
      });

      // The desktop start screen: no ground, the mark in its colour and
      // the name in white under it, the mark's height half the screen's
      // short side, on a desktop.
      const dw = 1280.0;
      const dh = 800.0;
      await save(t, '$dir/splash.png', dw.toInt(), dh.toInt(), (c) {
        c.drawRect(
          const Rect.fromLTWH(0, 0, dw, dh),
          Paint()
            ..shader = ui.Gradient.radial(
              const Offset(dw / 2, dh / 2),
              dw * 0.7,
              [const Color(0xFF2A2D36), const Color(0xFF14151A)],
            ),
        );
        final mark = math.min(dw, dh) * 0.5;
        final name = label('Anisched', mark * 0.16, Colors.white, bold: true);
        final top = (dh - mark - name.height * 1.2) / 2;
        c.save();
        c.translate((dw - mark) / 2, top);
        m.paint(c, mark, ground: false);
        c.restore();
        name.paint(c, Offset((dw - name.width) / 2, top + mark * 0.9));
      });
    });
  }
}
