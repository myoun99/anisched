import 'package:flutter/material.dart';

import 'theme.dart';

/// Open/closed state of the cut blocks, kept while the app runs and shared
/// by every unit (open one list's cuts and the next opens the same way).
abstract final class Folds {
  /// The deadline's rounds under a unit's details (folded at first).
  static final dueRounds = ValueNotifier<bool>(false);

  /// The cut chips under an opened list line. Closed by default: the
  /// line's facts come first.
  static final cutsInDetails = ValueNotifier<bool>(false);

  /// The register screen's grid of new cuts. Open: it is the screen's job.
  static final newCuts = ValueNotifier<bool>(true);

  /// The register screen's grid of an episode's saved cuts.
  static final savedCuts = ValueNotifier<bool>(false);
}

/// A small 「컷 n ▸」 toggle that opens or closes a block of cuts.
class FoldToggle extends StatelessWidget {
  const FoldToggle({super.key, required this.state, required this.label});

  final ValueNotifier<bool> state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: state,
      builder: (context, open, _) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => state.value = !open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: c.muted,
              ),
              Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
