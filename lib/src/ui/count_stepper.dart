import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'instant.dart';
import 'theme.dart';

/// A whole number of at least 1 with − and + beside it, under a caption
/// and what the number makes ([preview], e.g. the cut it names). One
/// widget for the register screen's first cut and count and the add-cuts
/// dialog's.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.label,
    required this.preview,
    required this.controller,
    required this.fieldKey,
    required this.onChanged,
  });

  final String label;
  final String preview;
  final TextEditingController controller;

  /// The text field's key (tests type into it).
  final Key fieldKey;

  /// After the number changed, by typing or a step.
  final VoidCallback onChanged;

  void _step(int by) {
    final v = (int.tryParse(controller.text) ?? 0) + by;
    controller.text = '${v < 1 ? 1 : v}';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget btn(IconData icon, int by) => InkWell(
      onTap: () => _step(by),
      child: SizedBox(width: 34, height: 36, child: Icon(icon, size: 18)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text.rich(
          TextSpan(
            text: '$label ',
            children: [
              TextSpan(
                text: preview,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(Icons.remove, -1),
              SizedBox(
                width: 64,
                child: TextField(
                  onTapOutside: unfocusOutside,
                  key: fieldKey,
                  controller: controller,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              btn(Icons.add, 1),
            ],
          ),
        ),
      ],
    );
  }
}
