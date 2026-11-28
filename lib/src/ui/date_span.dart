import 'package:flutter/material.dart';

import 'theme.dart';

/// Two dates as one span: a word before it (「제작」, 「작업」), then one pill
/// holding [start] → [end], the start on the left, and [trailing] after
/// the end (its D-n, the deadline's round). Each date is its own button
/// (given here). One widget for every unit's details and the register
/// screen's stage rows.
class DateSpanPill extends StatelessWidget {
  const DateSpanPill({
    super.key,
    required this.label,
    required this.start,
    required this.end,
    this.trailing = const [],
  });

  final String label;
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
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
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
