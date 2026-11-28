import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The dependency direction of CLAUDE.md, checked on every file:
/// core < models < services < controllers, each importing only inward;
/// platform/ sits above services and below ui/ and may reach
/// `flutter/services` (and `flutter/foundation` beneath it), no further.
/// None of these layers imports ui/ or the widget framework.
void main() {
  test('every layer imports only inward', () {
    expect(violations('lib/src'), isEmpty);
  });

  test('a wrong import is caught', () {
    // Passing proves nothing unless the check can fail: plant three
    // offences and expect each.
    final root = Directory.systemTemp.createTempSync('arch');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/models/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import '../services/b.dart';
import 'package:anisched/src/ui/c.dart';
import 'package:flutter/widgets.dart';
import '../core/ok.dart';
''');
    File('${root.path}/platform/p.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'package:flutter/services.dart';\n");
    expect(violations(root.path), [
      'models/a.dart: ../services/b.dart',
      'models/a.dart: package:anisched/src/ui/c.dart',
      'models/a.dart: package:flutter/widgets.dart',
    ]);
  });
}

const _layers = ['core', 'models', 'services', 'controllers', 'platform'];

/// Which layers each layer may import (itself included).
const _allowed = {
  'core': {'core'},
  'models': {'core', 'models'},
  'services': {'core', 'models', 'services'},
  'controllers': {'core', 'models', 'services', 'controllers'},
  'platform': {'core', 'models', 'services', 'platform'},
};

/// `file: import` pairs allowed against the rules. Keep it empty.
const _ledger = <String>{};

bool _flutterAllowed(String layer, String uri) =>
    layer == 'platform' &&
    (uri == 'package:flutter/services.dart' ||
        uri == 'package:flutter/foundation.dart');

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// Every import under [root] (a `lib/src`) against the direction, as
/// `layer/file: uri`, in file order.
List<String> violations(String root) {
  final out = <String>[];
  for (final layer in _layers) {
    final dir = Directory('$root/$layer');
    if (!dir.existsSync()) continue;
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final rel = f.path
          .replaceAll(r'\', '/')
          .substring(Directory(root).path.length + 1);
      for (final line in f.readAsLinesSync()) {
        final uri = _import.firstMatch(line)?[1];
        if (uri == null) continue;
        String? target;
        if (uri.startsWith('package:anisched/src/')) {
          target = uri.substring('package:anisched/src/'.length).split('/')[0];
        } else if (uri.startsWith('package:flutter/')) {
          if (!_flutterAllowed(layer, uri)) out.add('$rel: $uri');
          continue;
        } else if (!uri.contains(':')) {
          // Relative: the first folder above the file's own layer.
          final parts = [...rel.split('/')..removeLast(), ...uri.split('/')];
          final stack = <String>[];
          for (final p in parts) {
            if (p == '..') {
              if (stack.isNotEmpty) stack.removeLast();
            } else if (p != '.') {
              stack.add(p);
            }
          }
          target = stack.isEmpty ? null : stack.first;
        }
        if (target == null) continue; // dart:*, other packages
        if (!_allowed[layer]!.contains(target) &&
            !_ledger.contains('$rel: $uri')) {
          out.add('$rel: $uri');
        }
      }
    }
  }
  return out;
}
