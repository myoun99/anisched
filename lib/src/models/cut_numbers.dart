/// Parsing what the user types to add many cuts at once. Pure Dart.
library;

/// The result of [parseCutNumbers]: the cut numbers in input order with
/// duplicates removed, and any pieces that could not be read.
class CutNumbersParse {
  const CutNumbersParse(this.numbers, this.errors);

  final List<String> numbers;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Ranges longer than this are refused as a likely typo.
const maxCutRange = 3000;

final _separators = RegExp(r'[,、，\s]+');
final _rangeMark = RegExp(r'\s*(?:~|〜|～|–|—|\.\.)\s*');
final _numbered = RegExp(r'^(\D*?)(\d+)$');

/// Reads cut numbers from [input]:
///
/// - Items are separated by commas (`,` `、`) or whitespace.
/// - A range uses `~`, `〜`, `–` (en dash), `—` or `..`: `C100~C110`,
///   `C100~110` (the end may drop the prefix), `C098~C102` (the start's
///   zero-padding is kept). Both ends must be a prefix plus digits.
/// - A plain hyphen is **not** a range: `C012-014` stays one cut number
///   (a shared cut). Split cuts like `C012A` are kept as typed.
CutNumbersParse parseCutNumbers(String input) {
  final numbers = <String>[];
  final seen = <String>{};
  final errors = <String>[];
  void add(String n) {
    if (seen.add(n)) numbers.add(n);
  }

  // Protect ranges written with spaces around the mark ("C1 ~ C3").
  final normalized = input.replaceAllMapped(_rangeMark, (_) => '~');
  for (final item in normalized.split(_separators)) {
    if (item.isEmpty) continue;
    final parts = item.split('~');
    if (parts.length == 1) {
      add(item);
      continue;
    }
    final range = parts.length == 2 ? _range(parts[0], parts[1]) : null;
    if (range == null) {
      errors.add(item);
    } else {
      range.forEach(add);
    }
  }
  return CutNumbersParse(numbers, errors);
}

List<String>? _range(String from, String to) {
  final a = _numbered.firstMatch(from);
  final b = _numbered.firstMatch(to);
  if (a == null || b == null) return null;
  final prefix = a[1]!;
  if (b[1]!.isNotEmpty && b[1] != prefix) return null;
  final start = int.parse(a[2]!);
  final end = int.parse(b[2]!);
  if (end < start || end - start >= maxCutRange) return null;
  final width = a[2]!.length;
  return [
    for (var n = start; n <= end; n++)
      '$prefix${n.toString().padLeft(width, '0')}',
  ];
}

/// The reverse of [parseCutNumbers]: writes [numbers] (in the order given)
/// compactly, joining runs of three or more consecutive numbers with the
/// same prefix and width into a range — `C100~C103, C105`. Anything else
/// is listed as is. Parsing the result gives the same numbers back.
String formatCutNumbers(List<String> numbers) {
  final out = <String>[];
  var i = 0;
  while (i < numbers.length) {
    final a = _numbered.firstMatch(numbers[i]);
    var j = i;
    if (a != null) {
      while (j + 1 < numbers.length) {
        final b = _numbered.firstMatch(numbers[j + 1]);
        final prev = _numbered.firstMatch(numbers[j])!;
        if (b == null ||
            b[1] != a[1] ||
            b[2]!.length != a[2]!.length ||
            int.parse(b[2]!) != int.parse(prev[2]!) + 1) {
          break;
        }
        j++;
      }
    }
    if (j - i >= 2) {
      out.add('${numbers[i]}~${numbers[j]}');
      i = j + 1;
    } else {
      out.add(numbers[i]);
      i++;
    }
  }
  return out.join(', ');
}

/// Thrown when typed cut numbers cannot all be read; [items] are the
/// pieces that failed.
class CutNumbersException implements Exception {
  CutNumbersException(this.items);

  final List<String> items;

  @override
  String toString() => 'CutNumbersException: ${items.join(', ')}';
}

/// The number of a shared cut made from [first] to [last]: `C012`+`C014`
/// → `C012-014` (the last's digits when the prefixes match), otherwise
/// `first-last`.
String sharedCutNumber(String first, String last) {
  final a = _numbered.firstMatch(first);
  final b = _numbered.firstMatch(last);
  if (a != null && b != null && a[1] == b[1]) return '$first-${b[2]}';
  return '$first-$last';
}
