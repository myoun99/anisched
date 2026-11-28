/// Getting the most words into a tight place — one rule for the whole app
/// (bars, card titles, chips, tabs, toolbars), after Anicel's
/// `word_condensation.dart`:
///
/// 1. the letter gaps give way first, at most [maxGapTightening] each, so
///    the glyphs keep their shapes;
/// 2. then the word narrows sideways (height kept), down to [minScaleX];
/// 3. only then is it cut from the right with an ellipsis.
///
/// A word cut short shows its whole self in a tooltip (hover with a mouse
/// or pen, long press on touch) unless the place's own long press is
/// taken — then the details show it in full.
library;

import 'package:flutter/material.dart';

/// The most one letter gap gives way, in pixels.
const double maxGapTightening = 1;

/// The narrowest a word is drawn before it is cut (70% of its width).
const double minScaleX = 0.7;

/// How a word of natural [width] with [gaps] letter gaps is set in [room]:
/// the letter spacing (≤ 0), the sideways scale (≤ 1) and whether it is
/// cut. Pure, so the rule is pinned without a widget.
({double spacing, double scaleX, bool cut}) fitWord({
  required double width,
  required int gaps,
  required double room,
}) {
  if (width <= room || room <= 0) return (spacing: 0, scaleX: 1, cut: false);
  // 1. Letter gaps, in quarter pixels, up to the limit.
  var spacing = 0.0;
  if (gaps > 0) {
    final perGap = (width - room) / gaps;
    final stepped = (perGap / 0.25).ceilToDouble() * 0.25;
    spacing = -(stepped < maxGapTightening ? stepped : maxGapTightening);
  }
  final tightened = width + spacing * gaps;
  if (tightened <= room) return (spacing: spacing, scaleX: 1, cut: false);
  // 2. Narrow sideways, in 64ths (Anicel's step), never under the floor.
  final ratio = (room / tightened * 64).floorToDouble() / 64;
  if (ratio >= minScaleX) return (spacing: spacing, scaleX: ratio, cut: false);
  // 3. At the floor and still too long: cut from the right.
  return (spacing: spacing, scaleX: minScaleX, cut: true);
}

/// One line of text that keeps to its width by [fitWord]'s rule.
class FitText extends StatelessWidget {
  FitText(
    String text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.tooltip = true,
  }) : span = TextSpan(text: text);

  const FitText.rich(
    this.span, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.tooltip = true,
  });

  final InlineSpan span;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Show the whole text on hover / long press when it is cut. Off where
  /// the place's own long press is taken.
  final bool tooltip;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          text: TextSpan(style: base, children: [span]),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final plain = span.toPlainText();
        final gaps = plain.runes.length > 1 ? plain.runes.length - 1 : 0;
        final fit = fitWord(
          width: painter.width,
          gaps: gaps,
          room: box.maxWidth,
        );
        final lineHeight = painter.height;
        painter.dispose();
        Widget text = Text.rich(
          TextSpan(
            style: fit.spacing == 0
                ? null
                : TextStyle(letterSpacing: fit.spacing),
            children: [span],
          ),
          style: style,
          maxLines: 1,
          softWrap: false,
          textAlign: textAlign,
          overflow: fit.cut ? TextOverflow.ellipsis : TextOverflow.clip,
        );
        if (fit.scaleX < 1 && box.maxWidth.isFinite) {
          final alignment = switch (textAlign) {
            TextAlign.right || TextAlign.end => Alignment.centerRight,
            TextAlign.center => Alignment.center,
            _ => Alignment.centerLeft,
          };
          // Laid out wider by 1/scale, then drawn narrow: the cut (if
          // any) falls where the narrowed word meets the room.
          text = ClipRect(
            child: OverflowBox(
              alignment: alignment,
              minWidth: 0,
              maxWidth: box.maxWidth / fit.scaleX,
              child: Transform.scale(
                scaleX: fit.scaleX,
                scaleY: 1,
                alignment: alignment,
                child: SizedBox(width: box.maxWidth / fit.scaleX, child: text),
              ),
            ),
          );
          text = SizedBox(width: box.maxWidth, height: lineHeight, child: text);
        }
        if (fit.cut && tooltip) {
          text = Tooltip(message: plain, child: text);
        }
        return text;
      },
    );
  }
}
