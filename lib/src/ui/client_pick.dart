import 'package:flutter/material.dart';

import '../services/catalogue_reader.dart';
import 'client_chip.dart';
import 'palette.dart';
import 'pick_field.dart';
import 'text/strings.dart';

/// The client picker with its colour swatch beside it: pick a registered
/// client, make one with 「+ 새로 만들기」, colour the picked one. One
/// widget for the register screen and the edit dialog.
class ClientPick extends StatelessWidget {
  const ClientPick({
    super.key,
    required this.picked,
    required this.reader,
    required this.colors,
    required this.onPicked,
    this.onCreate,
    this.onColor,
    this.width = 220,
  });

  final PickOption<int>? picked;
  final CatalogueReader? reader;

  /// Colours of the clients the picker has shown (its search answers),
  /// filled in as it searches; the swatch shows the picked one's.
  final Map<int, int?> colors;
  final ValueChanged<PickOption<int>> onPicked;

  /// Makes a client of the typed name, returning its id; null hides
  /// 「새로 만들기」.
  final int Function(String name)? onCreate;

  /// Sets the picked client's colour (ARGB), after it is in [colors]
  /// (the parent rebuilds to show it); null hides the swatch.
  final void Function(int clientId, int argb)? onColor;
  final double width;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      PickField<int>(
        key: const Key('pick-client'),
        current: picked?.value,
        label: S.client.t,
        width: width,
        value: picked?.title,
        search: (q) async {
          final r = reader;
          if (r == null) return const [];
          final found = await r.searchClients(q);
          for (final x in found) {
            colors[x.id] = x.color;
          }
          return [
            for (final x in found) (value: x.id, title: x.name, note: null),
          ];
        },
        onPicked: onPicked,
        onCreate: onCreate == null
            ? null
            : (name) async => (value: onCreate!(name), title: name, note: null),
      ),
      if (picked case final cl? when onColor != null)
        ClientColorButton(
          color: clientColorOf(cl.value, colors[cl.value]),
          swatches: clientSwatches,
          tooltip: S.client.t,
          onPicked: (col) {
            colors[cl.value] = col.toARGB32();
            onColor!(cl.value, col.toARGB32());
          },
        ),
    ],
  );
}
