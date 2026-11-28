/// How cut and episode numbers are written (유저 2026-11-28): a prefix
/// and zero-padded digits, one setting each for the whole document — the
/// user types only the number.
library;

/// A prefix (`C`, `#`, none, or the user's own) and how many digits the
/// number is padded to.
typedef NumberStyle = ({String prefix, int digits});

/// Fewest digits a [NumberStyle] pads to.
const int minStyleDigits = 1;

/// Most digits a [NumberStyle] pads to.
const int maxStyleDigits = 8;

/// Cuts: `C001`.
const NumberStyle defaultCutStyle = (prefix: 'C', digits: 3);

/// Episodes: `#01`.
const NumberStyle defaultEpisodeStyle = (prefix: '#', digits: 2);

/// A cut number in [style]: 1 → `C001`.
String formatCutNumber(int number, NumberStyle style) => _format(number, style);

/// An episode number in [style]: 7 → `#07`.
String formatEpisodeNumber(int number, NumberStyle style) =>
    _format(number, style);

String _format(int number, NumberStyle style) =>
    '${style.prefix}${number.toString().padLeft(style.digits, '0')}';
