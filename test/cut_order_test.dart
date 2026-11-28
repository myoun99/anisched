import 'package:anisched/src/controllers/registration.dart';
import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/number_style.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// One cut order everywhere (유저 2026-11-28): numbers by value, then names
/// that are not numbers in the order they were added.
void main() {
  const c3 = (prefix: 'C', digits: 3);

  test('numbers by value, then names in the order they came', () {
    expect(
      sortedByCutNumber([
        '13',
        'CAM',
        '12B',
        '7',
        'BANK1',
        '12',
        '12A',
        'A1',
        '100',
      ], (n) => n),
      ['7', '12', '12A', '12B', '13', '100', 'CAM', 'BANK1', 'A1'],
    );
    // Shown numbers, read in a style.
    expect(
      sortedByCutNumber(['C013', 'C012A', 'BANK1', 'C007'], (n) => n, c3),
      ['C007', 'C012A', 'C013', 'BANK1'],
    );
    expect(compareCutNumbers('12A', '12B'), lessThan(0));
    expect(compareCutNumbers('BANK1', 'CAM'), 0); // tied: added order decides
  });

  test('the store reads cuts in that order on every path, names as added', () {
    final db = openAppDatabase(':memory:');
    addTearDown(db.close);
    final store = CatalogueStore(db, clock: () => DateTime(2026, 11, 28));
    final work = store.createWork('작품');
    final lo = store.stages(work).firstWhere((s) => s.name == 'LO').id;
    final ep = store.addEpisode(work, '1');
    final part = store.addPart(ep, 'A');
    store.addCuts(ep, [
      'CAM',
      'C013',
      'BANK1',
      'C012B',
      'C7',
      'C012A',
    ], partId: part);
    store
      ..addTasksForPart(part, lo)
      ..setEpisodeRate(ep, lo, const Rate(RateUnit.fixed, 1));
    const expected = ['C007', 'C012A', 'C012B', 'C013', 'CAM', 'BANK1'];

    expect(store.cuts(ep).map((c) => c.number), expected);
    expect(store.partGroups().single.tasks.map((t) => t.cutNumber), expected);
    final unit = store
        .statsTree(from: DateTime(2026, 11), to: DateTime(2026, 12))
        .children
        .single
        .children
        .single
        .children
        .single
        .children
        .single;
    expect(unit.children.map((c) => c.label), expected);

    // A renamed cut takes its new place.
    final cam = store.cuts(ep).firstWhere((c) => c.number == 'CAM').id;
    store.renumberCuts({cam: 'C010'});
    expect(store.cuts(ep).map((c) => c.number), [
      'C007',
      'C010',
      'C012A',
      'C012B',
      'C013',
      'BANK1',
    ]);
  });

  test('the registration draft lays its cells out in that order', () {
    final draft = CutDraft(count: 3)
      ..add('BANK1')
      ..add('C002A')
      ..add('CAM')
      ..add('C010');
    expect(draft.cells, [
      'C001',
      'C002',
      'C002A',
      'C003',
      'C010',
      'BANK1',
      'CAM',
    ]);
  });

  test('v21: existing cuts take the order', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    migrate(db, steps: migrations.where((m) => m.version <= 20).toList());
    db
      ..execute(
        "INSERT INTO works (title, currency, created_at) VALUES ('W', 'JPY', 0)",
      )
      ..execute(
        "INSERT INTO episodes (work_id, number, sort_key) VALUES (1, '1', '')",
      )
      ..execute('''
INSERT INTO cuts (episode_id, number, sort_key) VALUES
  (1, 'CAM', 'cam'), (1, '12A', ''), (1, 'BANK1', 'bank0000000001'),
  (1, '7', '')''');
    migrate(db);
    expect(
      db
          .select('SELECT number FROM cuts ORDER BY sort_key, id')
          .map((r) => r['number']),
      ['7', '12A', 'CAM', 'BANK1'],
    );
  });
}
