import 'package:anisched/src/services/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app database opens with foreign keys on', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    expect(db.select('PRAGMA foreign_keys;').first.values.first, 1);
  });
}
