import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/progress.dart';
import 'package:anisched/src/models/number_style.dart';
import 'package:anisched/src/ui/format.dart';
import 'package:anisched/src/ui/text/strings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_catalogue.dart';

const r = TaskStatus.received;
const w = TaskStatus.inProgress;
const s = TaskStatus.submitted;
const t = TaskStatus.retake;

void main() {
  test('cuts left are the ones not yet submitted', () {
    final store = sampleCatalogue(DateTime(2026, 11, 27, 14));
    // 별빛 #07 part C: 5 cuts, one submitted.
    final c = store.partGroups().firstWhere(
      (g) => g.workTitle == '별빛 정류장' && g.partLabel == 'C',
    );
    expect(c.total, 5);
    expect(cutsLeftLabel(c), '4 cut');
  });

  group('dueLabel', () {
    final now = DateTime(2026, 11, 27, 15);
    DateTime on(int day) => DateTime(2026, 11, day, 23, 59);

    test('counts whole local days from the production deadline', () {
      expect(dueLabel(on(30), now, w).text, 'D-3');
      expect(dueLabel(on(27), now, w).text, 'D-day');
      expect(dueLabel(on(25), now, w).text, 'D+2');
    });

    test('only a missed deadline on open work stands out', () {
      expect(dueLabel(on(29), now, w).tone, DueTone.quiet);
      expect(dueLabel(on(27), now, r).tone, DueTone.quiet);
      expect(dueLabel(on(25), now, t).tone, DueTone.late);
    });

    test('the deadline signal and the dashboard write days the same way', () {
      expect(dueDaysText(-1), 'D+1');
      expect(dueSignalLabel(const DueLate(1)).text, 'D+1');
      expect(dueSignalLabel(const DueDaysLeft(0)).text, 'D-day');
    });

    test('handed-in work never looks late', () {
      expect(dueLabel(on(25), now, s), (text: '—', tone: DueTone.none));
      expect(dueLabel(null, now, w).text, '—');
    });

    test('a late day start keeps the small hours on the previous day', () {
      final late = DateTime(2026, 11, 28, 2);
      expect(dueLabel(on(27), late, w).text, 'D+1');
      expect(dueLabel(on(27), late, w, dayStartMinutes: 4 * 60).text, 'D-day');
    });
  });

  test('formatLength writes seconds+frames at 24 fps', () {
    expect(formatLength(3500), '3+12');
    expect(formatLength(2000), '2+00');
    expect(formatLength(750), '0+18');
    expect(formatLength(null), '—');
  });

  test('formatMoney uses the currency sign and separators', () {
    expect(formatMoney('JPY', 4500), '¥4,500');
    expect(formatMoney('KRW', 900000), '₩900,000');
    expect(formatMoney('JPY', 0), '¥0');
    expect(formatMoney('EUR', 1234567), 'EUR 1,234,567');
  });

  test('totals keep currencies apart', () {
    final groups = sampleCatalogue(DateTime(2026, 11, 27)).partGroups();
    final totals = totalsByCurrency(groups);
    expect(totals.keys, ['JPY', 'KRW']);
    expect(totals['KRW'], 900000);
  });

  test('a storyboard reads as one item, a part by its label', () {
    final groups = sampleCatalogue(DateTime(2026, 11, 27)).partGroups();
    final conte = groups.firstWhere((g) => g.kind == GroupKind.storyboard);
    expect(groupTitle(conte), '콘티');
    expect(groupCount(conte), '1건');
    final part = groups.firstWhere((g) => g.kind == GroupKind.part);
    expect(groupTitle(part), endsWith('파트'));
  });

  test('a part-less unit reads as its cut range, gaps and all', () {
    final store = sampleCatalogue(DateTime(2026, 11, 27));
    final work = store.works().first.id;
    final ep = store.addEpisode(work, '30');
    final stage = store.stages(work).first.id;
    for (final n in ['C001', 'C002', 'C003', 'C007', 'C008']) {
      store.addTask(stage, cutId: store.addCut(ep, n));
    }
    final loose = store.partGroups().firstWhere(
      (g) => g.kind == GroupKind.noPart,
    );
    expect(groupTitle(loose), 'C001~C003, C007, C008');
  });

  test('a typed episode number reads as it will once stored', () {
    addTearDown(() => episodeStyle.value = defaultEpisodeStyle);
    expect(episodeShown('7'), '#07');
    expect(episodeShown('#7'), '#07');
    expect(episodeShown(' 12 '), '#12');
    expect(episodeShown('SP'), 'SP');
    episodeStyle.value = (prefix: '', digits: 3);
    expect(episodeShown('7'), '007');
  });

  test('stages read in the user language; typed names stay', () {
    addTearDown(() => appLang.value = Lang.ko);
    appLang.value = Lang.ja;
    expect(stageText('원화/작감'), '原画/作監');
    expect(stageText('LO'), 'LO');
    expect(stageText('리테이크'), 'リテイク');
    appLang.value = Lang.en;
    expect(stageText('동화/동검'), 'IB/IBC');
    expect(stageText('내 공정'), '내 공정');
    appLang.value = Lang.ko;
    expect(stageText('원화/작감'), '원화/작감');
  });
}
