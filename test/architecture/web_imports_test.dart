import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web build's ratchet: following `lib/main.dart`'s imports and exports
/// the way the web compiler does (the `if (dart.library.js_interop)`
/// branch of every conditional one), no file reaches what only devices
/// have — `dart:io`, `dart:ffi`, `dart:isolate`, the native SQLite
/// binding or path_provider. Those live in the `*_io.dart` branches.
void main() {
  test('the web build reaches no device-only library', () {
    expect(deviceOnlyOnWeb('lib/main.dart', web: true), isEmpty);
  });

  test('the walk finds them on the device branch (the check can fail)', () {
    final found = deviceOnlyOnWeb('lib/main.dart', web: false);
    expect(found, contains('boot_io.dart: dart:io'));
    expect(
      found,
      contains('src/services/catalogue_reader_background.dart: dart:isolate'),
    );
  });
}

const _deviceOnly = {
  'dart:io',
  'dart:ffi',
  'dart:isolate',
  'package:sqlite3/sqlite3.dart',
  'package:path_provider/path_provider.dart',
};

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]'''
  r'''(?:\s+if\s*\(\s*dart\.library\.js_interop\s*\)\s*['"]([^'"]+)['"])?''',
  multiLine: true,
);

/// `file: library` for every device-only library reached from [entry]
/// (a path under `lib/`), taking the web branch of conditional directives
/// when [web].
List<String> deviceOnlyOnWeb(String entry, {required bool web}) {
  final seen = <String>{};
  final found = <String>[];
  void visit(String path) {
    if (!seen.add(path)) return;
    final text = File(path).readAsStringSync();
    for (final m in _directive.allMatches(text)) {
      final uri = web && m[2] != null ? m[2]! : m[1]!;
      if (_deviceOnly.contains(uri)) {
        found.add('${path.substring('lib/'.length)}: $uri');
        continue;
      }
      final next = _resolve(path, uri);
      if (next != null) visit(next);
    }
  }

  visit(entry);
  found.sort();
  return found;
}

/// The file [uri] names from [from], or null outside this package.
String? _resolve(String from, String uri) {
  if (uri.startsWith('package:anisched/')) {
    return 'lib/${uri.substring('package:anisched/'.length)}';
  }
  if (uri.contains(':')) return null;
  final parts = from.split('/')..removeLast();
  for (final p in uri.split('/')) {
    if (p == '..') {
      parts.removeLast();
    } else if (p != '.') {
      parts.add(p);
    }
  }
  return parts.join('/');
}
