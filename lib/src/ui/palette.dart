/// Stage and client colours: bars take their stage's colour, clients a
/// swatch of their own. Until the data's colours arrive (v17:
/// `stageColorOf`, `clientColor`) each name or id picks a stable tone here.
library;

import 'package:flutter/material.dart';

/// Cream tones for bars: light enough that dark ink reads on them in
/// both themes.
const stageTones = [
  Color(0xFFF3E2B3), // butter
  Color(0xFFF2CFB6), // peach
  Color(0xFFDDE6BF), // sage
  Color(0xFFC9E2DA), // mint
  Color(0xFFD3DCF1), // periwinkle
  Color(0xFFE6D3EA), // lilac
  Color(0xFFF0D0D0), // rose
  Color(0xFFE5DAC4), // sand
];

/// The ink on a cream bar (light and dark mode alike).
const barInk = Color(0xFF2E2A24);

/// Client swatches: stronger, to read as a small square beside a name.
const clientSwatches = [
  Color(0xFF3B6FE0),
  Color(0xFFE0843B),
  Color(0xFF2E9E6B),
  Color(0xFFB0459B),
  Color(0xFFD94B4B),
  Color(0xFF7A5BD6),
  Color(0xFF2B9BB0),
  Color(0xFF8C7A3A),
];

int _stable(String s) =>
    s.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x7fffffff);

/// A stage's bar colour (stand-in until the data gives it).
Color stageColor(String stageName) =>
    stageTones[_stable(stageName) % stageTones.length];

/// A client's swatch (stand-in until the data gives it).
Color clientColorOf(int clientId) =>
    clientSwatches[clientId % clientSwatches.length];
