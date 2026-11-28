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

// ---- stored values (유저 2026-11-28: 표기 = 표시만) ----
//
// A cut or episode number is stored as its value — the number without
// prefix or padding, plus any letters after it (`12A` for a split cut) —
// and shown in the current style. A name that is not a number in that
// sense (`BANK1`, `SP`) is stored and shown as typed.

final _typedValue = RegExp(r'^0*(\d{1,9})([A-Za-z]*)$');
final _storedValue = RegExp(r'^(0|[1-9]\d{0,8})([A-Z]*)$');

/// What to store for [typed] (유저 2026-11-28 — a number is its value,
/// however it was typed): spaces dropped; a leading `C`, `#` or the
/// style's own prefix (any case) dropped when a number follows; leading
/// zeros dropped; letters after the number in capitals — `C012`, `c12`,
/// `012`, `12` → `12`; `12a` → `12A`. Anything that is not a number so
/// read (`BANK1`, `SP`) is kept as typed, trimmed.
String storedNumber(String typed, NumberStyle style) {
  final t = typed.replaceAll(RegExp(r'\s+'), '');
  final m = _typedValue.firstMatch(_withoutPrefix(t, style.prefix));
  return m == null ? typed.trim() : '${int.parse(m[1]!)}${m[2]!.toUpperCase()}';
}

/// [t] without the first of [prefix], `C` and `#` it starts with (any
/// case) that leaves a number.
String _withoutPrefix(String t, String prefix) {
  for (final p in {prefix, 'C', '#'}) {
    if (p.isEmpty || t.length <= p.length) continue;
    if (t.substring(0, p.length).toLowerCase() != p.toLowerCase()) continue;
    final rest = t.substring(p.length);
    if (_typedValue.hasMatch(rest)) return rest;
  }
  return t;
}

/// A cut number as typed → its stored value ([storedNumber]).
String parseCutInput(String typed, NumberStyle style) =>
    storedNumber(typed, style);

/// An episode number as typed → its stored value ([storedNumber]).
String parseEpisodeInput(String typed, NumberStyle style) =>
    storedNumber(typed, style);

/// How a [stored] number reads in [style]: `12A` → `C012A`; a typed name
/// stays as it is.
String shownNumber(String stored, NumberStyle style) {
  final m = _storedValue.firstMatch(stored);
  return m == null ? stored : '${_format(int.parse(m[1]!), style)}${m[2]}';
}
