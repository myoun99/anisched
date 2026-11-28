// A reader whose statistics come from three months of made-up work, so
// the captures show full charts. Capture-only.
import 'dart:math' as math;

import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/models/stats.dart';
import 'package:anisched/src/models/work_interval.dart';
import 'package:anisched/src/services/catalogue_reader.dart';

class RichStatsReader extends SyncCatalogueReader {
  RichStatsReader(super.store, this.now);

  final DateTime now;

  @override
  Future<Stats> stats({
    required DateTime from,
    required DateTime to,
    StatsBucket bucket = StatsBucket.week,
  }) async {
    final (facts, intervals) = _made(now);
    Stats run(DateTime a, DateTime b) => computeStats(
      facts: facts,
      intervals: intervals,
      from: a,
      to: b,
      now: now,
      bucket: bucket,
    );
    final s = run(from, to);
    final span = to.difference(from);
    s.previous = run(from.subtract(span), from);
    s.stagePaces = const [
      StagePace(
        stageName: '원화',
        overall: UsualPace(stageName: '원화', cuts: 410, workDays: 120),
        recent: UsualPace(stageName: '원화', cuts: 92, workDays: 24),
      ),
      StagePace(
        stageName: 'LO',
        overall: UsualPace(stageName: 'LO', cuts: 260, workDays: 52),
        recent: UsualPace(stageName: 'LO', cuts: 60, workDays: 10),
      ),
      StagePace(
        stageName: '작감 수정',
        overall: UsualPace(stageName: '작감 수정', cuts: 300, workDays: 40),
        recent: UsualPace(stageName: '작감 수정', cuts: 38, workDays: 6),
      ),
    ];
    return s;
  }
}

(List<StatsFact>, List<WorkInterval>) _made(DateTime now) {
  final r = math.Random(7);
  final works = [
    (1, '별빛 정류장', 'JPY', 1, '스튜디오 하루', 4500),
    (2, '마법소녀 리코', 'JPY', 2, '미라이 애니메', 3800),
    (3, '푸른 늑대의 숲', 'KRW', 3, '서울 픽처스', 30000),
  ];
  const stages = ['원화', '원화', 'LO', '작감 수정'];
  final facts = <StatsFact>[];
  final intervals = <WorkInterval>[];
  var id = 0;
  for (var back = 120; back > 0; back--) {
    final day = DateTime(now.year, now.month, now.day - back);
    if (day.weekday == DateTime.sunday) continue;
    final n = day.weekday == DateTime.saturday
        ? r.nextInt(2)
        : 2 + r.nextInt(5);
    for (var k = 0; k < n; k++) {
      final w = works[r.nextInt(back > 60 ? 2 : 3)];
      final take = r.nextDouble() < 0.72 ? 1 : (r.nextDouble() < 0.75 ? 2 : 3);
      final handed = day.add(Duration(hours: 13 + r.nextInt(10)));
      final due = handed.add(
        Duration(days: r.nextInt(6) - (r.nextDouble() < 0.18 ? 6 : 1)),
      );
      final ext = r.nextDouble() < 0.2 ? 1 + r.nextInt(2) : 0;
      id++;
      final worked = Duration(minutes: 25 + r.nextInt(70));
      facts.add(
        StatsFact(
          taskId: id,
          stageName: stages[r.nextInt(stages.length)],
          workId: w.$1,
          workTitle: w.$2,
          currency: w.$3,
          clientId: w.$4,
          clientName: w.$5,
          groupKey: 'g${w.$1}-${back ~/ 9}',
          take: take,
          submittedAt: handed.toUtc(),
          doneAt: handed.add(Duration(days: 2 + r.nextInt(4))).toUtc(),
          dueAt: due.toUtc(),
          dueExtensions: ext,
          firstDueAt: due.subtract(Duration(days: ext * 3)).toUtc(),
          planStartAt: day.subtract(Duration(days: r.nextInt(4))),
          planEndAt: day.add(Duration(days: r.nextInt(3))),
          pay: w.$6,
          worked: worked,
        ),
      );
      final start = day.add(
        Duration(hours: 10 + r.nextInt(12), minutes: r.nextInt(60)),
      );
      intervals.add(
        WorkInterval(
          id: id,
          taskId: id,
          start: start.toUtc(),
          stop: start.add(worked).toUtc(),
        ),
      );
    }
  }
  for (var i = 0; i < 40; i++) {
    id++;
    facts.add(
      StatsFact(
        taskId: id,
        stageName: '원화',
        workId: 3,
        workTitle: '푸른 늑대의 숲',
        currency: 'KRW',
        clientId: 3,
        clientName: '서울 픽처스',
        groupKey: 'open',
      ),
    );
  }
  return (facts, intervals);
}
