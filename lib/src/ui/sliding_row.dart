import 'package:flutter/material.dart';

/// A row of chips or buttons the finger slides sideways when it does not
/// fit, with no scrollbar under it (vertical lists and charts keep
/// theirs). Every such row in the app is this one widget.
class SlidingRow extends StatelessWidget {
  const SlidingRow({
    super.key,
    required this.children,
    this.spacing = 6,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: spacing,
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      ),
    ),
  );
}
