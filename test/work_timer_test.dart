import 'dart:io';

import 'package:anisched/src/models/work_interval.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/work_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 27, 9);
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = t0);

  group('WorkInterval', () {
    test('a running interval counts up to now', () {
      final i = WorkInterval(id: 1, start: t0);
      expect(
        i.elapsed(t0.add(const Duration(minutes: 5))),
        const Duration(minutes: 5),
      );
    });

    test('a stopped interval ignores now', () {
      final i = WorkInterval(
        id: 1,
        start: t0,
        stop: t0.add(const Duration(minutes: 30)),
      );
      expect(
        i.elapsed(t0.add(const Duration(days: 3))),
        const Duration(minutes: 30),
      );
    });

    test('elapsed is never negative', () {
      final i = WorkInterval(id: 1, start: t0);
      expect(i.elapsed(t0.subtract(const Duration(hours: 1))), Duration.zero);
    });

    test('clipping splits work across midnight', () {
      final i = WorkInterval(
        id: 1,
        start: DateTime.utc(2026, 11, 27, 23),
        stop: DateTime.utc(2026, 11, 28, 2),
      );
      final midnight = DateTime.utc(2026, 11, 28);
      expect(
        i.elapsedWithin(DateTime.utc(2026, 11, 27), midnight, midnight),
        const Duration(hours: 1),
      );
      expect(
        i.elapsedWithin(midnight, DateTime.utc(2026, 11, 29), midnight),
        const Duration(hours: 2),
      );
    });

    test('totalElapsed sums intervals', () {
      final list = [
        WorkInterval(id: 1, start: t0, stop: t0.add(const Duration(hours: 1))),
        WorkInterval(id: 2, start: t0.add(const Duration(hours: 2))),
      ];
      expect(
        totalElapsed(list, t0.add(const Duration(hours: 3))),
        const Duration(hours: 2),
      );
    });
  });

  group('WorkTimerStore', () {
    test('start then stop records the interval', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock);
      store.start();
      now = t0.add(const Duration(minutes: 42));
      final stopped = store.stop()!;
      expect(stopped.elapsed(now), const Duration(minutes: 42));
      expect(store.running(), isNull);
    });

    test('a second start while running is refused', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock)..start();
      expect(store.start, throwsA(isA<TimerAlreadyRunningException>()));
    });

    test('stop with nothing running returns null', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      expect(WorkTimerStore(db, clock: clock).stop(), isNull);
    });

    test('a running timer survives the app being killed and relaunched', () {
      final dir = Directory.systemTemp.createTempSync('anisched');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.db';

      final first = openAppDatabase(path);
      WorkTimerStore(first, clock: clock).start();
      first.close(); // the process dies; nothing else is written

      now = t0.add(const Duration(hours: 2, minutes: 15));
      final second = openAppDatabase(path);
      addTearDown(second.close);
      final store = WorkTimerStore(second, clock: clock);
      final open = store.running()!;
      expect(open.start, t0);
      expect(open.elapsed(now), const Duration(hours: 2, minutes: 15));

      now = now.add(const Duration(minutes: 45));
      expect(store.stop()!.elapsed(now), const Duration(hours: 3));
    });

    test('a clock that went backwards stops at zero length', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock)..start();
      now = t0.subtract(const Duration(minutes: 10));
      final stopped = store.stop()!;
      expect(stopped.stop, t0);
      expect(stopped.elapsed(now), Duration.zero);
    });

    test('workedBetween clips to the range and includes a running timer', () {
      final db = openAppDatabase(':memory:');
      addTearDown(db.close);
      final store = WorkTimerStore(db, clock: clock);
      now = DateTime.utc(2026, 11, 27, 22);
      store.start();
      now = DateTime.utc(2026, 11, 28, 1);
      store.stop();
      now = DateTime.utc(2026, 11, 28, 3);
      store.start();
      now = DateTime.utc(2026, 11, 28, 4);

      final day27 = store.workedBetween(
        DateTime.utc(2026, 11, 27),
        DateTime.utc(2026, 11, 28),
      );
      final day28 = store.workedBetween(
        DateTime.utc(2026, 11, 28),
        DateTime.utc(2026, 11, 29),
      );
      expect(day27, const Duration(hours: 2));
      expect(day28, const Duration(hours: 2));
    });
  });
}
