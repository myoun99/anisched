// Timings on a large synthetic document, to compare before and after a
// change. Not part of `flutter test` (it is slow on purpose); run it with
//   flutter test tool/bench/bench_test.dart
// and read the table it prints. Numbers are the median of [runs] runs, in
// milliseconds, on a file database (WAL), as the app uses it.

import 'dart:io';

import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/services/catalogue_reader.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/document_codec.dart';
import 'package:anisched/src/services/undo_history.dart';
import 'package:flutter_test/flutter_test.dart';

const runs = 5;
const works = 20;
const episodes = 5;
const parts = 4;
const cutsPerPart = 25; // 20 × 5 × 4 × 25 = 10,000 cuts
// LO and 원화 on every cut: 20,000 tasks.

final now = DateTime(2026, 11, 27, 14);

void main() {
  test('bench', () async {
    final dir = Directory.systemTemp.createTempSync('anisched-bench');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/bench.db';
    final rows = <(String, double)>[];
    double median(List<double> xs) => (xs..sort())[xs.length ~/ 2];
    double time(void Function() f) {
      final sw = Stopwatch()..start();
      f();
      return sw.elapsedMicroseconds / 1000;
    }

    Future<double> timeAsync(Future<void> Function() f) async {
      final sw = Stopwatch()..start();
      await f();
      return sw.elapsedMicroseconds / 1000;
    }

    void bench(String name, void Function() f) {
      f(); // warm-up
      rows.add((name, median([for (var i = 0; i < runs; i++) time(f)])));
    }

    // ---- build ----
    var db = openAppDatabase(path);
    var store = CatalogueStore(db, clock: () => now);
    final build = time(() => _fill(store));
    final tasks = db.select('SELECT COUNT(*) AS n FROM tasks').first['n'];
    final cuts = db.select('SELECT COUNT(*) AS n FROM cuts').first['n'];
    rows.add(('build ($tasks tasks, $cuts cuts)', build));

    // ---- reads on the main isolate (the store) ----
    bench('taskRows', () => store.taskRows());
    bench('partGroups', () => store.partGroups());
    bench('calendarLayout', () => store.calendarLayout());
    bench('today', () => store.today());
    bench('signals', () => store.signals());
    bench('stagePaces', () => store.stagePaces());
    bench(
      'stats (year, month buckets)',
      () => store.stats(
        from: DateTime(2026),
        to: DateTime(2027),
        bucket: StatsBucket.month,
      ),
    );
    bench(
      'statsTree (year, $cuts cuts)',
      () => store.statsTree(from: DateTime(2026), to: DateTime(2027)),
    );
    bench(
      'events + holidays (a month)',
      () => store
        ..events(from: DateTime(2026, 11), to: DateTime(2026, 12))
        ..holidays(from: DateTime(2026, 11), to: DateTime(2026, 12)),
    );

    // ---- one date write, as a bar dropped after a drag ----
    final part = db.select('SELECT id FROM parts LIMIT 1').first['id'] as int;
    final stage =
        db.select('SELECT id FROM work_stages LIMIT 1').first['id'] as int;
    store
      ..clearLanePins()
      ..clearGroupOrder();
    rows.add((
      'date write, first (holds every place)',
      time(
        () => store.setPartDue(part, stage, now.add(const Duration(days: 3))),
      ),
    ));
    var day = 4;
    bench(
      'date write, places held',
      () => store.setPartDue(part, stage, now.add(Duration(days: day++))),
    );

    // ---- the same writes with the undo history recording ----
    final history = UndoHistory.attach(db);
    bench(
      'date write, places held, with undo history',
      () => store.setPartDue(part, stage, now.add(Duration(days: day++))),
    );
    final undoTask =
        db.select('SELECT id FROM tasks LIMIT 1').first['id'] as int;
    bench('status write, with undo history', () {
      store.setStatus(undoTask, TaskStatus.inProgress);
      store.setStatus(undoTask, TaskStatus.received);
    });
    await history.detach();
    bench('status write, no history', () {
      store.setStatus(undoTask, TaskStatus.inProgress);
      store.setStatus(undoTask, TaskStatus.received);
    });
    UndoHistory.attach(db);
    // One step of many rows: a whole part's tasks deleted, then undone.
    final bigPart =
        db.select('SELECT id FROM parts LIMIT 1 OFFSET 7').first['id'] as int;
    final partTasks = [
      for (final r in db.select(
        'SELECT t.id FROM tasks t JOIN cuts c ON c.id = t.cut_id '
        'WHERE c.part_id = ?',
        [bigPart],
      ))
        r['id'] as int,
    ];
    rows.add((
      'delete a part (${partTasks.length} tasks), with undo history',
      time(() => store.deleteTasks(partTasks)),
    ));
    await Future<void>.value();
    rows.add(('undo that delete', time(() => UndoHistory.of(db)!.undo())));
    await UndoHistory.of(db)!.detach();

    // ---- document out and in ----
    final out = '${dir.path}/out.anisched';
    rows.add((
      'save (export, VACUUM INTO)',
      median([
        for (var i = 0; i < 3; i++)
          await timeAsync(() => exportDocument(path, out)),
      ]),
    ));
    final copy = '${dir.path}/in.anisched';
    rows.add((
      'open (check + migrate + replace rows)',
      median([
        for (var i = 0; i < 3; i++)
          await timeAsync(() async {
            File(out).copySync(copy);
            await prepareImport(copy);
            importDocumentInto(db, copy);
          }),
      ]),
    ));

    // ---- start: open the file, the reader, the first read ----
    db.close();
    final start = <double>[];
    for (var i = 0; i < 3; i++) {
      start.add(
        await timeAsync(() async {
          db = openAppDatabase(path);
          final reader = await BackgroundCatalogueReader.open(path, writer: db);
          await reader.partGroups();
          await reader.close();
          db.close();
        }),
      );
    }
    rows.add(('start: open + reader + first partGroups', median(start)));
    final boot = <double>[];
    for (var i = 0; i < 3; i++) {
      boot.add(
        await timeAsync(() async {
          db = openAppDatabase(path);
          final reader = await BackgroundCatalogueReader.open(path, writer: db);
          await reader.close();
          db.close();
        }),
      );
    }
    rows.add((
      'start: open + reader ready (before the first frame)',
      median(boot),
    ));
    db = openAppDatabase(path);
    store = CatalogueStore(db, clock: () => now);
    final reader = await BackgroundCatalogueReader.open(path, writer: db);
    rows.add((
      'reader partGroups (isolate round trip)',
      median([
        for (var i = 0; i < runs; i++) await timeAsync(reader.partGroups),
      ]),
    ));
    rows.add((
      'reader statsTree (isolate round trip)',
      median([
        for (var i = 0; i < 3; i++)
          await timeAsync(
            () => reader.statsTree(from: DateTime(2026), to: DateTime(2027)),
          ),
      ]),
    ));
    await reader.close();
    db.close();

    // ignore: avoid_print
    print(
      [
        '| measure | ms |',
        '|---|---:|',
        for (final (name, ms) in rows) '| $name | ${ms.toStringAsFixed(1)} |',
      ].join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// 20 works × 5 episodes × 4 parts × 25 cuts, LO and 원화 on each, with
/// deadlines, plans, statuses, timer stretches and events spread around.
void fillForProbe(CatalogueStore store) => _fill(store);

void _fill(CatalogueStore store) {
  final db = store.db;
  db.execute('BEGIN');
  var n = 0;
  for (var w = 0; w < works; w++) {
    final client = store.addClient('회사 $w', color: 0xFF000000 + w);
    final work = store.createWork('작품 $w', clientId: client);
    final stages = [
      for (final s in store.stages(work))
        if (s.name == 'LO' || s.name == '원화') s.id,
    ];
    for (var e = 0; e < episodes; e++) {
      final ep = store.addEpisode(work, '#${e + 1}');
      for (final s in stages) {
        store.setEpisodeRate(ep, s, const Rate(RateUnit.fixed, 3000));
      }
      for (var p = 0; p < parts; p++) {
        final part = store.addPart(ep, String.fromCharCode(65 + p));
        store.addCuts(
          ep,
          [for (var c = 0; c < cutsPerPart; c++) 'C${p * cutsPerPart + c + 1}'],
          partId: part,
          lengthMs: 3000,
        );
        for (final s in stages) {
          final ids = store.addTasksForPart(part, s);
          final offset = (w * 7 + e * 3 + p) % 60 - 20;
          db
            ..execute(
              'INSERT INTO part_stage_dues (part_id, stage_id, due_at) '
              'VALUES (?, ?, ?);',
              [part, s, now.add(Duration(days: offset)).millisecondsSinceEpoch],
            )
            ..execute(
              'INSERT INTO part_stage_plans (part_id, stage_id, start_at, '
              'end_at) VALUES (?, ?, ?, ?);',
              [
                part,
                s,
                now.add(Duration(days: offset - 10)).millisecondsSinceEpoch,
                now.add(Duration(days: offset - 1)).millisecondsSinceEpoch,
              ],
            );
          for (final id in ids) {
            final status = switch (n++ % 6) {
              0 || 1 || 2 => TaskStatus.submitted,
              3 => TaskStatus.inProgress,
              4 => TaskStatus.retake,
              _ => TaskStatus.received,
            };
            if (status != TaskStatus.received) store.setStatus(id, status);
            if (n % 4 == 0) {
              // Straight in: the timer refuses overlaps, and this is data.
              final at = now.subtract(Duration(minutes: 30 * (n ~/ 4) + 60));
              db.execute(
                'INSERT INTO work_intervals (started_at, stopped_at, task_id) '
                'VALUES (?, ?, ?);',
                [
                  at.millisecondsSinceEpoch,
                  at.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
                  id,
                ],
              );
            }
          }
        }
      }
      store.addEvent(
        episodeId: ep,
        date: now.add(Duration(days: e)),
        title: '아후레코',
      );
    }
  }
  store.addRestDays(DateTime(2026, 12, 29), end: DateTime(2027, 1, 3));
  db.execute('COMMIT');
}
