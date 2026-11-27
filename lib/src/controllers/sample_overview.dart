/// Example data matching mock-up v4, shown until the catalogue's read API
/// lands. Deadlines are relative to [sampleOverview]'s `today`.
library;

import '../models/catalogue.dart';
import 'overview.dart';

typedef _Cut = (String, TaskStatus, int, String, double, int?);

const _r = TaskStatus.received;
const _w = TaskStatus.inProgress;
const _s = TaskStatus.submitted;
const _t = TaskStatus.retake;
const _d = TaskStatus.done;

List<PartStage> sampleOverview(DateTime today) {
  final day0 = DateTime(today.year, today.month, today.day, 23, 59);
  DateTime at(int days) => day0.add(Duration(days: days));
  var nextId = 1;

  int lengthMs(String sec) {
    final p = sec.split('+');
    return int.parse(p[0]) * 1000 + (int.parse(p[1]) * 1000 / 24).round();
  }

  PartStage part(
    String work,
    String currency,
    String episode,
    String? label,
    String stage,
    int due,
    List<_Cut> cuts, {
    int Function(int lengthMs)? payOf,
    int? fixed,
  }) {
    return PartStage(
      key: '$work/$episode/$label/$stage',
      workTitle: work,
      currency: currency,
      episode: episode,
      partLabel: label,
      stage: stage,
      dueAt: at(due),
      plannedCount: cuts.length,
      tasks: [
        for (final (cut, st, take, sec, h, ov) in cuts)
          TaskItem(
            id: nextId++,
            label: cut,
            status: st,
            take: take,
            lengthMs: lengthMs(sec),
            dueAt: at(ov ?? due),
            dueFromPart: ov == null,
            pay: payOf?.call(lengthMs(sec)) ?? fixed,
            worked: Duration(minutes: (h * 60).round()),
          ),
      ],
    );
  }

  int perSecond(int rate, int ms) => rate * ((ms + 500) ~/ 1000);

  return [
    part('별빛 정류장', 'JPY', '#07', 'B', 'LO', -6, fixed: 3000, [
      ('C030', _d, 1, '2+06', 1.5, null),
      ('C031', _d, 1, '1+12', 1.0, null),
      ('C032', _d, 2, '5+00', 2.5, null),
      ('C033', _d, 1, '3+00', 1.5, null),
    ]),
    part('별빛 정류장', 'JPY', '#07', 'B', '원화', 2, fixed: 4500, [
      ('C030', _s, 2, '2+06', 5.5, null),
      ('C031', _d, 1, '1+12', 3.0, null),
      ('C032', _d, 3, '5+00', 7.5, null),
      ('C033', _w, 1, '3+00', 2.0, null),
    ]),
    part('별빛 정류장', 'JPY', '#07', 'A', '원화', 0, fixed: 4500, [
      ('C012', _w, 1, '3+12', 4.5, null),
      ('C014', _r, 1, '2+00', 0, null),
      ('C015', _t, 2, '4+06', 6.0, null),
      ('C021', _w, 1, '1+18', 1.5, 2),
    ]),
    part('별빛 정류장', 'JPY', '#07', 'C', 'LO', 4, fixed: 3000, [
      ('C044', _t, 3, '2+18', 2.5, 1),
      ('C045', _r, 1, '0+18', 0, null),
      ('C046', _w, 1, '3+06', 1.0, null),
      ('C047', _r, 1, '2+12', 0, null),
      ('C048', _s, 1, '1+06', 1.0, null),
    ]),
    part('마법소녀 리코', 'JPY', '#11', 'A', 'LO 작감 수정', 3, fixed: 1500, [
      ('C101', _w, 1, '2+00', 0.8, null),
      ('C102', _r, 1, '1+06', 0, null),
      ('C103', _r, 1, '2+12', 0, null),
      ('C104', _r, 1, '3+00', 0, null),
      ('C116', _s, 1, '1+12', 0.6, null),
    ]),
    part('마법소녀 리코', 'JPY', '#11', 'B', '원화 작감 수정', 1, fixed: 2000, [
      ('C108', _s, 1, '3+18', 1.5, null),
      ('C109', _t, 2, '2+00', 1.2, -1),
      ('C110', _d, 1, '1+00', 0.7, null),
      ('C111', _d, 1, '4+12', 1.3, null),
      ('C115', _w, 1, '2+06', 0.5, null),
      ('C120', _d, 2, '3+00', 1.0, null),
    ]),
    part(
      '푸른 늑대의 숲',
      'JPY',
      '극장판',
      'C',
      'LO',
      10,
      payOf: (ms) => perSecond(5000, ms),
      [
        ('C0312', _w, 1, '6+00', 3.0, null),
        ('C0313', _r, 1, '4+12', 0, null),
        ('C0318', _s, 1, '5+06', 5.0, 7),
      ],
    ),
    part(
      '푸른 늑대의 숲',
      'JPY',
      '극장판',
      'A',
      '원화',
      3,
      payOf: (ms) => perSecond(10000, ms),
      [
        ('C0290', _d, 2, '4+00', 11.0, null),
        ('C0291', _t, 2, '3+06', 9.0, null),
        ('C0295', _w, 1, '2+12', 2.0, null),
      ],
    ),
    PartStage(
      key: '여름 끝에서/MV/콘티',
      workTitle: '여름 끝에서',
      currency: 'KRW',
      episode: 'MV',
      stage: '콘티',
      isStoryboard: true,
      dueAt: at(6),
      tasks: [
        TaskItem(
          id: nextId++,
          label: '콘티',
          status: _w,
          dueAt: at(6),
          pay: 900000,
          worked: const Duration(hours: 8),
        ),
      ],
    ),
  ];
}
