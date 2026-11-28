import 'package:flutter/material.dart';

import 'theme.dart';

/// Two dates as one span: a word before it (「스케줄」, 「작업 예상」), then
/// one pill holding [start] → [end], the start on the left, and [trailing]
/// after the end (the deadline's round). Each date is its own button
/// (given here). One widget for every unit's details and the register
/// screen's stage rows.
class DateSpanPill extends StatelessWidget {
  const DateSpanPill({
    super.key,
    required this.label,
    required this.start,
    required this.end,
    this.trailing = const [],
    this.labelWidth,
  });

  final String label;

  /// The head's width, to line up pills stacked on rows ([headWidth]);
  /// null: as wide as its text.
  final double? labelWidth;

  static const _headStyle = TextStyle(fontSize: 12);

  /// The width the widest of [labels] needs as a head.
  static double headWidth(BuildContext context, List<String> labels) {
    final scaler = MediaQuery.textScalerOf(context);
    var w = 0.0;
    for (final l in labels) {
      final p = TextPainter(
        text: TextSpan(
          text: l,
          style: DefaultTextStyle.of(context).style.merge(_headStyle),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (p.width > w) w = p.width;
      p.dispose();
    }
    return w.ceilToDouble() + 1;
  }

  final Widget start;
  final Widget end;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: _headStyle.copyWith(color: c.muted),
          ),
        ),
        // On the narrowest phones it shrinks a little rather than spill.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    start,
                    Icon(Icons.arrow_forward, size: 13, color: c.muted),
                    end,
                    ...trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
