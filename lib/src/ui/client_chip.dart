/// A client as every screen shows it: a small square of its colour and
/// its name, on a card-like chip. One widget wherever a client appears.
library;

import 'package:flutter/material.dart';

import 'fit_text.dart';
import 'theme.dart';

/// A client's name and colour, as the views pass it around.
typedef ClientTag = ({String name, Color color});

class ClientChip extends StatelessWidget {
  const ClientChip(this.client, {super.key, this.compact = false});

  final ClientTag client;

  /// Only the square, with the name's first letter (tight places); the
  /// name shows on hover / long press.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final square = DecoratedBox(
      decoration: BoxDecoration(
        color: client.color,
        borderRadius: BorderRadius.circular(compact ? 4 : 2.5),
      ),
      child: SizedBox.square(
        dimension: compact ? 20 : 10,
        child: compact
            ? Center(
                child: Text(
                  client.name.characters.firstOrNull ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              )
            : null,
      ),
    );
    if (compact) return Tooltip(message: client.name, child: square);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            square,
            Flexible(
              child: FitText(client.name, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A client's colour, picked from a row of swatches (the register
/// screen, beside the client).
class ClientColorButton extends StatelessWidget {
  const ClientColorButton({
    super.key,
    required this.color,
    required this.swatches,
    required this.onPicked,
    this.tooltip,
  });

  final Color color;
  final List<Color> swatches;
  final ValueChanged<Color> onPicked;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget square(Color col, {bool on = false}) => DecoratedBox(
      decoration: BoxDecoration(
        color: col,
        borderRadius: BorderRadius.circular(5),
        border: on ? Border.all(color: c.muted, width: 2) : null,
      ),
      child: const SizedBox.square(dimension: 26),
    );
    return PopupMenuButton<Color>(
      key: const Key('client-color'),
      tooltip: tooltip ?? '',
      onSelected: onPicked,
      itemBuilder: (_) => [
        PopupMenuItem<Color>(
          enabled: false,
          child: SizedBox(
            width: 4 * 34,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, s) in swatches.indexed)
                  InkWell(
                    key: Key('client-color-$i'),
                    onTap: () => Navigator.of(context).pop(s),
                    child: square(s, on: s == color),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          alignment: Alignment.center,
          children: [
            square(color),
            const Icon(Icons.palette_outlined, size: 15, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
