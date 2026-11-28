/// Stage names (공정) as 「work/checker」 — `LO`, `LO/연출`, `원화/작감` —
/// taken from Anicel's colour labels (유저 2026-11-28): the work axis is
/// Anicel's `LayerProcess` without 용지 (paper is no stage), the checker
/// axis its `LayerRevise`, and a work offers only its own checkers
/// (Anicel's `revisesFor`). The keys are Anicel's, so the UI can show the
/// five-language names from Anicel's string table (`layerProcess.*`,
/// `layerRevise.*`). Stored names are the Korean short forms below; any
/// other name the user types is kept as typed.
library;

/// The work axis (Anicel `LayerProcess`, 용지 left out).
///
/// Colours: Anicel's layer-mark palette, cream column
/// (`layer_mark_palette.dart`, set pixel by pixel by the user).
enum StageWork {
  conte('conte', '콘티', 0xFFD1BAF7),
  layout('layout', 'LO', 0xFFFFFDF7),
  roughKey('rough-key', '러프원', 0xFFAEFCF2),
  key('key', '원화', 0xFFB5FDB0),
  inbetween('inbetween', '동화', 0xFFFFF2C2),
  finish('finish', '시아게', 0xFFF2BDB7);

  const StageWork(this.id, this.korean, this.color);

  /// Anicel's key (`layerProcess.<id>`).
  final String id;

  /// The stored Korean short form (Anicel `layerProcessAbbrev`, ko).
  final String korean;

  /// ARGB.
  final int color;
}

/// The checker axis (Anicel `LayerRevise`).
///
/// A check has its checker's colour whatever the work: `LO/작감` and
/// `원화/작감` are both 작감's. 연출 · 작감 · 총작감 · 감독 · 총감독 are
/// Anicel's cream column; 액션 · 동검 · 셀검 are **제안** (proposals —
/// not in that palette).
enum StageCheck {
  direction('direction', '연출', 0xFFFFC1E8),
  animationDirector('animation-director', '작감', 0xFFFFC663),
  chiefAnimationDirector('chief-animation-director', '총작감', 0xFFEDFDCE),
  director('director', '감독', 0xFFC0BEF7),
  chiefDirector('chief-director', '총감독', 0xFFD7BEF7),
  actionAnimationDirector('action-animation-director', '액션', 0xFFFFD9B0),
  inbetweenCheck('inbetween-check', '동검', 0xFFF5E6A8),
  cellCheck('cell-check', '셀검', 0xFFF7D0D6);

  const StageCheck(this.id, this.korean, this.color);

  /// Anicel's key (`layerRevise.<id>`).
  final String id;

  /// The stored Korean short form (Anicel `layerReviseAbbrev`, ko).
  final String korean;

  /// ARGB.
  final int color;
}

/// Stages outside the two axes (유저 2026-11-28). Their colours are
/// **제안** (proposals — Anicel has no such marks).
enum StageExtra {
  characterDesign('character-design', '캐릭터디자인', 0xFFE6D3C3),

  /// Work that comes back from the rushes (ラッシュ): 「이 컷은 작감이
  /// 수정해 주세요」.
  retake('retake', '리테이크', 0xFFFF9E9E);

  const StageExtra(this.id, this.korean, this.color);

  final String id;
  final String korean;

  /// ARGB.
  final int color;
}

/// The colour of the stage named [name] (ARGB): its checker's when it is
/// a check, else its work's, else its own (character design, retake);
/// null for a name the user typed (the view's default). The one place a
/// stage's colour comes from — once stages can be edited, a user's own
/// colour will be looked up here first.
int? stageColorOf(String name) {
  final label = stageLabelOf(name);
  return label?.check?.color ?? label?.work?.color ?? label?.extra?.color;
}

const _drawingChecks = [
  StageCheck.direction,
  StageCheck.animationDirector,
  StageCheck.chiefAnimationDirector,
  StageCheck.director,
  StageCheck.chiefDirector,
  StageCheck.actionAnimationDirector,
];

/// The checkers [work] offers (Anicel `revisesFor`, paper aside).
List<StageCheck> checksFor(StageWork work) => switch (work) {
  StageWork.conte => const [StageCheck.director, StageCheck.chiefDirector],
  StageWork.inbetween => const [..._drawingChecks, StageCheck.inbetweenCheck],
  StageWork.finish => const [..._drawingChecks, StageCheck.cellCheck],
  _ => _drawingChecks,
};

/// A stage's stored name: `LO`, `LO/작감`.
String stageName(StageWork work, [StageCheck? check]) =>
    check == null ? work.korean : '${work.korean}/${check.korean}';

/// What a stored stage name means, for showing it in the user's language;
/// null for a name the user typed themselves.
typedef StageLabel = ({StageWork? work, StageCheck? check, StageExtra? extra});

StageLabel? stageLabelOf(String name) {
  for (final e in StageExtra.values) {
    if (e.korean == name) return (work: null, check: null, extra: e);
  }
  final parts = name.split('/');
  if (parts.length > 2) return null;
  final work = StageWork.values.where((w) => w.korean == parts[0]).firstOrNull;
  if (work == null) return null;
  if (parts.length == 1) return (work: work, check: null, extra: null);
  final check = checksFor(work).where((c) => c.korean == parts[1]).firstOrNull;
  return check == null ? null : (work: work, check: check, extra: null);
}

/// Every name the two axes allow, in order — for a stage picker.
List<String> get allStageNames => [
  for (final w in StageWork.values) ...[
    stageName(w),
    for (final c in checksFor(w)) stageName(w, c),
  ],
  for (final e in StageExtra.values) e.korean,
];

/// The old 「… 수정」 names (and 콘티 체크) and what they are now — the
/// v14 migration renames stored stages with this.
const Map<String, String> legacyStageNames = {
  '콘티 체크': '콘티/감독',
  'LO 연출 수정': 'LO/연출',
  'LO 작감 수정': 'LO/작감',
  'LO 총작감 수정': 'LO/총작감',
  '원화 연출 수정': '원화/연출',
  '원화 작감 수정': '원화/작감',
  '원화 총작감 수정': '원화/총작감',
};
