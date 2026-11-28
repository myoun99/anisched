import 'package:anisched/src/models/catalogue.dart';
import 'package:anisched/src/models/stage_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a work offers only its own checkers', () {
    expect(checksFor(StageWork.conte), [
      StageCheck.director,
      StageCheck.chiefDirector,
    ]);
    expect(checksFor(StageWork.inbetween), contains(StageCheck.inbetweenCheck));
    expect(
      checksFor(StageWork.inbetween),
      isNot(contains(StageCheck.cellCheck)),
    );
    expect(checksFor(StageWork.finish), contains(StageCheck.cellCheck));
    expect(checksFor(StageWork.key), hasLength(6));
  });

  test('names read back as work/checker; typed names are nobody\'s', () {
    expect(stageLabelOf('LO'), (
      work: StageWork.layout,
      check: null,
      extra: null,
    ));
    expect(stageLabelOf('원화/작감'), (
      work: StageWork.key,
      check: StageCheck.animationDirector,
      extra: null,
    ));
    expect(stageLabelOf('리테이크')?.extra, StageExtra.retake);
    expect(stageLabelOf('콘티/작감'), isNull); // 콘티 has no 작감
    expect(stageLabelOf('LO/작감/연출'), isNull);
    expect(stageLabelOf('용지'), isNull);
    expect(stageLabelOf('LO 작감 수정'), isNull);
  });

  test('a stage takes its checker\'s colour, else its work\'s', () {
    expect(stageColorOf('원화'), 0xFFB5FDB0);
    expect(stageColorOf('LO'), 0xFFFFFDF7);
    expect(stageColorOf('LO/작감'), 0xFFFFC663);
    expect(stageColorOf('원화/작감'), stageColorOf('LO/작감'));
    expect(stageColorOf('콘티/감독'), 0xFFC0BEF7);
    expect(stageColorOf('리테이크'), StageExtra.retake.color);
    expect(stageColorOf('내 공정'), isNull);
  });

  test('every allowed name reads back, and the default preset is allowed', () {
    for (final n in allStageNames) {
      expect(stageLabelOf(n), isNotNull, reason: n);
    }
    expect(allStageNames.toSet(), containsAll(defaultStageNames));
    expect(allStageNames.toSet(), hasLength(allStageNames.length));
    for (final n in legacyStageNames.values) {
      expect(stageLabelOf(n), isNotNull, reason: n);
    }
  });
}
