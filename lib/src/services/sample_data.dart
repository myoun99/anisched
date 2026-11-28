import '../models/catalogue.dart';
import 'catalogue_store.dart';

/// Fills [store] with a small example catalogue — four works, a few parts
/// in every state, a storyboard — so a first look (the web preview's
/// 「예시 데이터 넣기」) and the widget tests have something to show.
/// Deadlines are relative to [now] (end of that local day). Written
/// through the store's own API, like the user's own entries.
void fillSample(CatalogueStore store, DateTime now) {
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

  // Each client its own colour, so the views show what colours do.
  final sky = store.addClient('스튜디오 하늘', color: 0xFF5B8DEF);
  final works = store.addClient('애니웍스', color: 0xFFF29A4B);
  final motion = store.addClient('모션랩', color: 0xFF4CB782);

  final star = store.createWork('별빛 정류장', clientId: sky);
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

  final riko = store.createWork('마법소녀 리코', clientId: works);
  final riko11 = store.addEpisode(riko, '#11');
  part(riko, riko11, 'B', '원화/작감', 1, const Rate(RateUnit.fixed, 2000), [
    ('C108', s, 1, '3+18', null),
    ('C109', t, 2, '2+00', -1),
    ('C110', d, 1, '1+00', null),
    ('C115', w, 1, '2+06', null),
  ]);

  final wolf = store.createWork('푸른 늑대의 숲', clientId: sky);
  final movie = store.addEpisode(wolf, '극장판');
  part(wolf, movie, 'A', '원화', 3, const Rate(RateUnit.perSecond, 10000), [
    ('C0290', d, 2, '4+00', null),
    ('C0291', t, 2, '3+06', null),
    ('C0295', w, 1, '2+12', null),
  ]);

  final mv = store.createWork('여름 끝에서', currency: 'KRW', clientId: motion);
  final mvEp = store.addEpisode(mv, 'MV');
  final conte = stage(mv, '콘티');
  store.setEpisodeRate(mvEp, conte, const Rate(RateUnit.fixed, 900000));
  final sb = store.addStoryboard(mvEp, '콘티');
  store.setStatus(store.addTask(conte, storyboardId: sb, dueAt: at(6)), w);

  // Events: one at a time of day, two all day.
  store
    ..addEvent(
      episodeId: star7,
      date: at(2),
      timeMinutes: 14 * 60,
      title: '아후레코',
    )
    ..addEvent(episodeId: riko11, date: at(5), title: '납품')
    ..addEvent(episodeId: movie, date: at(1), title: '작화 회의');
}
