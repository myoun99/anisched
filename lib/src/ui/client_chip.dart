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
