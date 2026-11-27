import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';

/// Mock-up v4's data, written through the real store into an in-memory
/// database. Deadlines are relative to [now] (end of that local day).
CatalogueStore sampleCatalogue(DateTime now) {
  final store = CatalogueStore(openAppDatabase(':memory:'), clock: () => now);
  final day = DateTime(now.year, now.month, now.day, 23, 59);
  DateTime at(int days) => day.add(Duration(days: days));

  int stage(int workId, String name) =>
      store.stages(workId).firstWhere((s) => s.name == name).id;

  int ms(String sec) {
    final p = sec.split('+');
    return int.parse(p[0]) * 1000 + (int.parse(p[1]) * 1000 / 24).round();
  }

  /// cuts: (number, status, take, length, own due in days or null)
  void part(
    int workId,
    int episodeId,
    String label,
    String stageName,
    int due,
    Rate rate,
    List<(String, TaskStatus, int, String, int?)> cuts, {
    (int, int)? plan,
  }) {
    final s = stage(workId, stageName);
    store.setEpisodeRate(episodeId, s, rate);
    final partId = store.addPart(
      episodeId,
      label,
      plannedCutCount: cuts.length,
    );
    store.setPartDue(partId, s, at(due));
    if (plan != null) {
      store.setPartPlan(partId, s, start: at(plan.$1), end: at(plan.$2));
    }
    for (final (number, status, take, len, own) in cuts) {
      final cutId = store.addCut(
        episodeId,
        number,
        lengthMs: ms(len),
        partId: partId,
      );
      final task = store.addTask(
        s,
        cutId: cutId,
        dueAt: own == null ? null : at(own),
      );
      for (var t = 2; t <= take; t++) {
        store.requestRetake(task);
      }
      store.setStatus(task, status);
    }
  }

  const r = TaskStatus.received;
  const w = TaskStatus.inProgress;
  const s = TaskStatus.submitted;
  const t = TaskStatus.retake;
  const d = TaskStatus.done;

  final star = store.createWork('별빛 정류장');
  final star7 = store.addEpisode(star, '#07');
  part(star, star7, 'B', 'LO', -6, const Rate(RateUnit.fixed, 3000), [
    ('C030', d, 1, '2+06', null),
    ('C031', d, 1, '1+12', null),
    ('C032', d, 2, '5+00', null),
    ('C033', d, 1, '3+00', null),
  ]);
  part(star, star7, 'A', '원화', 0, const Rate(RateUnit.fixed, 4500), [
    ('C012', w, 1, '3+12', null),
    ('C014', r, 1, '2+00', null),
    ('C015', t, 2, '4+06', null),
    ('C021', w, 1, '1+18', 2),
  ]);
  part(
    star,
    star7,
    'C',
    'LO',
    4,
    const Rate(RateUnit.fixed, 3000),
    [
      ('C044', t, 3, '2+18', 1),
      ('C045', r, 1, '0+18', null),
      ('C046', w, 1, '3+06', null),
      ('C047', r, 1, '2+12', null),
      ('C048', s, 1, '1+06', null),
    ],
    plan: (-1, 6),
  );

  final riko = store.createWork('마법소녀 리코');
  final riko11 = store.addEpisode(riko, '#11');
  part(riko, riko11, 'B', '원화 작감 수정', 1, const Rate(RateUnit.fixed, 2000), [
    ('C108', s, 1, '3+18', null),
    ('C109', t, 2, '2+00', -1),
    ('C110', d, 1, '1+00', null),
    ('C115', w, 1, '2+06', null),
  ]);

  final wolf = store.createWork('푸른 늑대의 숲');
  final movie = store.addEpisode(wolf, '극장판');
  part(wolf, movie, 'A', '원화', 3, const Rate(RateUnit.perSecond, 10000), [
    ('C0290', d, 2, '4+00', null),
    ('C0291', t, 2, '3+06', null),
    ('C0295', w, 1, '2+12', null),
  ]);

  final mv = store.createWork('여름 끝에서', currency: 'KRW');
  final mvEp = store.addEpisode(mv, 'MV');
  final conte = stage(mv, '콘티');
  store.setEpisodeRate(mvEp, conte, const Rate(RateUnit.fixed, 900000));
  final sb = store.addStoryboard(mvEp, '콘티');
  store.setStatus(store.addTask(conte, storyboardId: sb, dueAt: at(6)), w);

  return store;
}
