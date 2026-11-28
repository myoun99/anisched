/// The app's words in its five languages. Every piece of screen text goes
/// through [S]; short tokens everyone reads (`cut`, `D-3`, `IN 12/10`) and
/// names the user typed stay as they are.
///
/// Industry terms follow Japanese studio usage (原画 · 作監 · LO · 絵コンテ)
/// and their usual equivalents elsewhere. Role and stage names are the
/// user's own data and are not translated.
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../../services/device_settings.dart';

/// A language the app ships.
enum Lang {
  en('en', 'English'),
  ja('ja', '日本語'),
  ko('ko', '한국어'),
  fr('fr', 'Français'),
  zhHans('zh', '简体中文');

  const Lang(this.code, this.native);

  /// Language code for [Locale].
  final String code;

  /// The language's own name, as the picker shows it.
  final String native;

  Locale get locale => this == zhHans
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
      : Locale(code);

  /// The first of [preferred] the app ships, else English.
  static Lang forLocales(Iterable<Locale> preferred) {
    for (final l in preferred) {
      for (final g in values) {
        if (g.code == l.languageCode) return g;
      }
    }
    return en;
  }
}

/// The language the screens show. Korean until the app resolves the
/// device's (tests read Korean).
final appLang = ValueNotifier<Lang>(Lang.ko);

/// This device's language choice (「기기」 follows the device). main.dart
/// saves it; the app resolves [appLang] from it.
final languageSetting = ValueNotifier<LanguageChoice>(LanguageChoice.device);

/// The language [choice] means on a device preferring [device].
Lang resolveLang(LanguageChoice choice, Iterable<Locale> device) =>
    switch (choice) {
      LanguageChoice.device => Lang.forLocales(device),
      LanguageChoice.en => Lang.en,
      LanguageChoice.ja => Lang.ja,
      LanguageChoice.ko => Lang.ko,
      LanguageChoice.fr => Lang.fr,
      LanguageChoice.zhHans => Lang.zhHans,
    };

/// Screen words: English, Japanese, Korean, French, Simplified Chinese.
/// `{name}` marks a value filled in by [f].
enum S {
  // Views.
  viewDashboard('Dashboard', 'ダッシュボード', '대시보드', 'Tableau de bord', '仪表板'),
  viewList('List', 'リスト', '목록', 'Liste', '列表'),
  viewTimeline('Timeline', 'タイムライン', '타임라인', 'Planning', '时间线'),
  viewWork('Work', '作業', '작업', 'Travail', '工作'),
  viewRegister('Add', '登録', '등록', 'Ajouter', '登记'),
  viewSettings('Settings', '設定', '설정', 'Réglages', '设置'),
  viewStats('Stats', '統計', '통계', 'Stats', '统计'),

  // Task status.
  stReceived('Received', '受取', '받음', 'Reçu', '已收到'),
  stInProgress('In progress', '作業中', '작업중', 'En cours', '进行中'),
  stSubmitted('Submitted', '提出', '제출', 'Remis', '已提交'),
  stRetake('Retake', 'リテイク', '리테이크', 'Retake', '返修'),

  // Counts and dates.
  daysLate('{n}d late', '{n}日超過', '{n}일 지남', '{n} j de retard', '超期{n}天'),
  days('{n}d', '{n}日', '{n}일', '{n} j', '{n}天'),
  items('{n}', '{n}件', '{n}건', '{n}', '{n}项'),
  monthLabel('{m}', '{m}月', '{m}월', '{m}', '{m}月'),
  today('Today', '今日', '오늘', "Aujourd'hui", '今天'),
  tomorrow('Tomorrow', '明日', '내일', 'Demain', '明天'),
  dashAsk('To do today', '今日の分', '오늘 할 컷', "À faire aujourd'hui", '今天要做'),
  dashHanded(
    'Handed in today',
    '今日渡した',
    '오늘 넘긴 컷',
    "Rendus aujourd'hui",
    '今天交付',
  ),
  dashWorked('Worked today', '今日の作業', '오늘 작업', "Travail aujourd'hui", '今天工作'),
  dashDue('Due soon', 'もうすぐ締切', '곧 마감', 'Bientôt dus', '即将截止'),
  dashAgenda(
    'Today · tomorrow',
    '今日・明日',
    '오늘·내일',
    "Aujourd'hui · demain",
    '今天·明天',
  ),
  dashAttention('Needs a look', '要確認', '주의', 'À surveiller', '需注意'),
  dashWeek('This week', '今週', '이번 주', 'Cette semaine', '本周'),
  dashHandedWeek('Handed in', '渡した数', '넘긴 컷', 'Rendus', '交付数'),

  // Units of work.
  partTitle('Part {p}', '{p}パート', '{p}파트', 'Partie {p}', '{p}部分'),
  noPart('No part', 'パートなし', '파트 없음', 'Sans partie', '无部分'),
  noClient('No client', '会社なし', '회사 없음', 'Sans client', '无公司'),
  storyboard('Storyboard', '絵コンテ', '콘티', 'Storyboard', '分镜'),

  // Plan signals.
  planOver(
    'Work ends after the deadline',
    '作業の終わりが締切より遅い',
    '실 작업 끝이 마감보다 늦음',
    "Le travail finit après l'échéance",
    '实际完成晚于截止',
  ),
  planHard(
    'Daily share over 1.5× your recent average',
    '1日の割当が最近の平均の1.5倍を超える',
    '하루 할당이 최근 평균의 1.5배를 넘음',
    'Part quotidienne > 1,5× la moyenne récente',
    '每日分配超过近期平均的1.5倍',
  ),
  planLateStart(
    'Start day has passed, not started yet',
    '作業開始日を過ぎたのにまだ未着手',
    '실 작업 시작일이 지났는데 아직 시작 전',
    'Date de début passée, pas encore commencé',
    '已过开始日期但尚未开始',
  ),
  planTight(
    'Daily share above your recent average',
    '1日の割当が最近の平均より多い',
    '하루 할당이 최근 평균보다 많음',
    'Part quotidienne au-dessus de la moyenne récente',
    '每日分配高于近期平均',
  ),

  // Top bar and list.
  sortByDue('By deadline', '締切順', '마감 순 정렬', 'Par échéance', '按截止排序'),
  clear('Clear', '解除', '해제', 'Effacer', '取消'),

  // Filter.
  fAll('All', 'すべて', '전체', 'Tout', '全部'),
  fLate('Overdue', '期限切れ', '지난 것', 'En retard', '已逾期'),
  fWithin3('Within 3 days', '3日以内', '3일 안', 'Sous 3 jours', '3天内'),
  fWithin14('Within 2 weeks', '2週間以内', '2주 안', 'Sous 2 semaines', '2周内'),
  fLater('Later', 'それ以降', '그 뒤', 'Plus tard', '之后'),
  fWithDone('With submitted', '提出済み含む', '제출 포함', 'Avec remis', '含已提交'),
  fPeriod('Period', '期間', '기간', 'Période', '期间'),
  client('Client', '会社', '회사', 'Client', '公司'),
  allClients('All clients', 'すべての会社', '모든 회사', 'Tous les clients', '所有公司'),
  title('Title', '作品', '작품', 'Titre', '作品'),
  allTitles('All titles', 'すべての作品', '모든 작품', 'Tous les titres', '所有作品'),
  showDone('Show submitted', '提出済みも表示', '제출한 것도 보기', 'Afficher remis', '显示已提交'),
  doneShown('Submitted shown', '提出済み表示', '제출 보임', 'Remis visibles', '显示已提交'),
  doneHidden('Submitted hidden', '提出済み非表示', '제출 숨김', 'Remis masqués', '隐藏已提交'),

  // File menu.
  fileNew('New', '新規', '새로', 'Nouveau', '新建'),
  fileOpen('Open', '開く', '열기', 'Ouvrir', '打开'),
  fileSave('Save', '保存', '저장', 'Enregistrer', '保存'),
  fileSaveAs('Save as', '名前を付けて保存', '다른 이름으로 저장', 'Enregistrer sous', '另存为'),
  fileExport(
    'Export to file',
    'ファイルに書き出す',
    '파일로 내보내기',
    'Exporter vers un fichier',
    '导出为文件',
  ),
  fileImport('Open a file', 'ファイルを開く', '파일 열기', 'Ouvrir un fichier', '打开文件'),
  emptyStart(
    'No work yet',
    'まだ作業がありません',
    '아직 작업이 없어요',
    'Aucun travail pour l’instant',
    '还没有工作',
  ),
  loadSample(
    'Add sample data',
    'サンプルを入れる',
    '예시 데이터 넣기',
    'Ajouter un exemple',
    '加入示例数据',
  ),
  untitled('Untitled', '無題', '무제', 'Sans titre', '未命名'),
  fileMissing(
    'File missing',
    'ファイルがない',
    '파일 없음',
    'Fichier introuvable',
    '文件不存在',
  ),
  saved('Saved', '保存済み', '저장됨', 'Enregistré', '已保存'),
  saving('Saving', '保存待ち', '저장 대기', 'À enregistrer', '待保存'),
  notSaved('Not saved', '未保存', '저장 안 됨', 'Non enregistré', '未保存'),

  // A document that would not open, save or read again.
  troubleUnreachable(
    'Can\'t reach the file',
    'ファイルに届きません',
    '파일에 닿을 수 없음',
    'Fichier inaccessible',
    '无法访问文件',
  ),
  troubleEmpty(
    'The file is empty (0 bytes): still downloading, or a save was cut off',
    'ファイルが空です（0 バイト）：ダウンロード中か、保存が途中で切れました',
    '파일이 비어 있음(0바이트) — 저장이 중간에 끊겼거나 아직 내려받는 중',
    'Fichier vide (0 octet) : encore en téléchargement, ou enregistrement interrompu',
    '文件为空（0 字节）：仍在下载，或保存被中断',
  ),
  troubleNotDocument(
    'Not an Anisched document',
    'Anisched の文書ではありません',
    'Anisched 문서가 아님',
    'Pas un document Anisched',
    '不是 Anisched 文档',
  ),
  troubleNewer(
    'Made by a newer Anisched: update the app',
    '新しい Anisched で作られた文書：アプリを更新してください',
    '더 새 Anisched 로 만든 문서: 앱을 업데이트하세요',
    'Créé par un Anisched plus récent : mettez l\'app à jour',
    '由更新版本的 Anisched 创建：请更新应用',
  ),
  troubleDamaged(
    'The file is damaged',
    'ファイルが壊れています',
    '파일이 손상됨',
    'Fichier endommagé',
    '文件已损坏',
  ),
  troubleOther(
    'Something went wrong with the file',
    'ファイルで問題が起きました',
    '파일에 문제가 생겼음',
    'Un problème est survenu avec le fichier',
    '文件出现问题',
  ),
  troubleUnfinished(
    'The save did not finish: trying again',
    '保存が最後まで終わりませんでした：再試行中',
    '저장이 끝까지 안 됨 — 다시 시도 중',
    'L\'enregistrement n\'a pas abouti : nouvel essai',
    '保存未完成：正在重试',
  ),
  troubleRestore(
    'Restore this device\'s last save',
    'この端末の最後の保存から復元',
    '이 기기의 마지막 저장본으로 복구',
    'Restaurer le dernier enregistrement de cet appareil',
    '用此设备上次的保存恢复',
  ),
  troubleNoCopy(
    'No saved copy on this device',
    'この端末に保存コピーがありません',
    '이 기기에 저장본이 없음',
    'Aucune copie enregistrée sur cet appareil',
    '此设备上没有保存副本',
  ),
  docRepaired(
    'Document restored',
    '文書を復元しました',
    '문서를 복구했어요',
    'Document restauré',
    '文档已恢复',
  ),
  troubleDetails('Details', '詳細', '자세히', 'Détails', '详情'),
  troubleCopy('Copy', 'コピー', '복사', 'Copier', '复制'),
  troubleCopied('Copied', 'コピーしました', '복사함', 'Copié', '已复制'),
  troubleRetry('Try again', '再試行', '다시 시도', 'Réessayer', '重试'),

  // Work lanes.
  autoPlace('Auto', '自動配置', '자동 배치', 'Auto', '自动排列'),
  overflow('Over', 'あふれ', '넘침', 'Excès', '溢出'),
  laneHead('Lanes', 'ライン', '라인', 'Lignes', '通道'),
  addLane('Add a lane', 'ラインを追加', '라인 추가', 'Ajouter une ligne', '添加通道'),
  deleteLane('Delete lane', 'ラインを削除', '라인 삭제', 'Supprimer la ligne', '删除通道'),
  laneN('Lane {n}', 'ライン {n}', '라인 {n}', 'Ligne {n}', '通道 {n}'),

  // Part line and details.
  part('Part', 'パート', '파트', 'Partie', '部分'),
  progress('Progress', '進捗', '진행', 'Avancement', '进度'),
  due('Due', '締切', '마감', 'Échéance', '截止'),
  // The production's dates and the user's own guess at their work: the
  // details' two date pills, the register's per-stage dates and what a
  // chart is drawn by (its toolbar's left).
  plannedDates('Schedule', 'スケジュール', '스케줄', 'Planning', '日程'),
  myEstimate('My estimate', '作業予定', '작업 예상', 'Mon estimation', '作业预计'),
  slack('Slack', '余裕', '여유', 'Marge', '余量'),
  perDay('Per day', '1日', '하루', 'Par jour', '每天'),
  rate('Rate', '単価', '단가', 'Tarif', '单价'),
  time('Time', '時間', '시간', 'Temps', '时间'),
  usual('Usual', '普段', '평소', 'Habituel', '平时'),
  recent('recent', '最近', '최근', 'récent', '近期'),

  // Settings.
  display('Display', '表示', '화면', 'Affichage', '显示'),
  themeSystem('System', 'システム', '시스템', 'Système', '系统'),
  themeLight('Light', 'ライト', '라이트', 'Clair', '浅色'),
  themeDark('Dark', 'ダーク', '다크', 'Sombre', '深色'),
  language('Language', '言語', '언어', 'Langue', '语言'),
  langDevice('Device', '端末', '기기', 'Appareil', '设备'),
  timerAuto(
    'Start timing when a cut is picked',
    'カットを選ぶとすぐ計測',
    '컷을 고르면 바로 기록 시작',
    'Chronométrer dès qu’un cut est choisi',
    '选中cut即开始计时',
  ),
  restWeekdays(
    'Weekly days off',
    '定休日',
    '쉬는 요일',
    'Repos hebdomadaire',
    '每周休息日',
  ),
  daysOff('Days off', '休み', '쉬는 날', 'Congés', '休息日'),
  viewMonths('By month', '月ごと', '달 보기', 'Par mois', '按月'),
  viewRunning('Running days', '日の流れ', '날 흐름 보기', 'Jours en continu', '连续日期'),
  holidays('Holidays', '祝日', '공휴일', 'Jours fériés', '节假日'),
  showHolidays(
    'Show holidays',
    '祝日を表示',
    '공휴일 표시',
    'Afficher les jours fériés',
    '显示节假日',
  ),
  restOnHolidays(
    'Rest on holidays',
    '祝日は休む',
    '공휴일에 쉬기',
    'Repos les jours fériés',
    '节假日休息',
  ),
  countryJapan('Japan', '日本', '일본', 'Japon', '日本'),
  countryKorea('Korea', '韓国', '한국', 'Corée', '韩国'),
  countryFrance('France', 'フランス', '프랑스', 'France', '法国'),
  countryChina('China', '中国', '중국', 'Chine', '中国'),
  countryNone('None', 'なし', '없음', 'Aucun', '无'),
  eventTitle('Title', 'タイトル', '제목', 'Titre', '标题'),
  eventTime('Time', '時刻', '시각', 'Heure', '时间'),
  allDay('All day', '終日', '하루 종일', 'Toute la journée', '全天'),
  eventNote('Note', 'メモ', '메모', 'Note', '备注'),
  remove('Remove', '削除', '지우기', 'Supprimer', '删除'),
  add('Add', '追加', '추가', 'Ajouter', '添加'),
  dayStart('Day starts at', '1日の始まり', '하루 시작', 'Début de journée', '一天开始于'),
  rounding(
    'Per-second rate rounding',
    '秒単価の端数',
    '초당 단가 반올림',
    'Arrondi du tarif/s',
    '按秒单价取整',
  ),
  rNearest('Round', '四捨五入', '반올림', 'Arrondir', '四舍五入'),
  rUp('Up', '切り上げ', '올림', 'Supérieur', '进位'),
  rDown('Down', '切り捨て', '버림', 'Inférieur', '舍去'),
  rExact('Exact', 'そのまま', '그대로', 'Exact', '不取整'),
  usualPace(
    'Usual pace (cut/day)',
    '普段のペース(1日 cut)',
    '평소 속도 (하루 cut)',
    'Rythme habituel (cut/jour)',
    '平时速度(每天 cut)',
  ),
  overwritten(
    'Overwritten copy',
    '上書きされた版',
    '덮어쓴 판',
    'Version écrasée',
    '被覆盖的版本',
  ),
  beforeChange('Before a change', '変更前', '바꾸기 전', 'Avant modification', '更改前'),
  revive('Bring back', '戻す', '되살리기', 'Rétablir', '还原'),
  monthHanded(
    'Submitted this month',
    '今月の提出',
    '이번 달 제출',
    'Remis ce mois-ci',
    '本月提交',
  ),
  unpriced(
    '{n} without rate',
    '単価なし {n}',
    '단가 없음 {n}',
    '{n} sans tarif',
    '无单价 {n}',
  ),
  storage('File', 'ファイル', '파일', 'Fichier', '文件'),

  // Registration.
  addCut('Add cut', 'カット追加', '컷 추가', 'Ajouter un cut', '添加 cut'),
  cutName('Cut name', 'カット名', '컷 이름', 'Nom du cut', 'cut 名'),
  registered('{n} added', '{n}件登録', '{n}건 등록', '{n} ajoutés', '已登记 {n} 项'),
  episode('Episode', '話数', '화수', 'Épisode', '集数'),
  roles('Roles', '担当', '담당', 'Rôles', '负责'),
  stagesN('{n} stages', '工程 {n}', '공정 {n}개', '{n} étapes', '{n} 个工序'),
  stage('Stage', '工程', '공정', 'Étape', '工序'),
  schedule('Schedule', '日程', '일정', 'Calendrier', '日程'),
  cutsToRegister(
    'Cuts to register',
    '登録するカット',
    '등록할 컷',
    'Cuts à enregistrer',
    '要登记的镜头',
  ),
  kickoff('Start', '着手', '착수', 'Début', '开工'),
  takeOut('Remove', '外す', '빼기', 'Retirer', '移除'),
  shared('Shared', '兼用', '겸용', 'Partagé', '兼用'),
  unshare('Unshare', '兼用解除', '겸용 풀기', 'Dissocier', '取消兼用'),
  name('Name', '名前', '이름', 'Nom', '名称'),
  register('Add', '登録', '등록', 'Ajouter', '登记'),
  resetForm('Reset', 'リセット', '초기화', 'Réinitialiser', '重置'),
  inUse('In use', '使用中', '사용 중', 'Utilisé', '使用中'),
  rulerRows('Ruler', '目盛り', '날짜 줄', 'Règle', '标尺'),
  statsSummary('Summary', '概要', '요약', 'Résumé', '概要'),
  statsTable('Table', '明細', '상세 표', 'Tableau', '明细'),
  colPay('Pay', '金額', '금액', 'Montant', '金额'),
  colRetakes('Retakes', 'リテイク', '리테이크', 'Retakes', '返修'),
  timerRuns(
    '{n} timer runs',
    'タイマー {n}回',
    '타이머 구간 {n}',
    '{n} chronos',
    '计时 {n} 段',
  ),
  retakeRound('Take {n}', 'T{n}', '{n}회차', 'Prise {n}', '第{n}次'),
  rulerYear('Year', '年', '년도', 'Année', '年'),
  rulerMonth('Month', '月', '월', 'Mois', '月'),
  rulerWeekday('Weekday', '曜日', '요일', 'Jour', '星期'),
  numberClashes(
    '{n} numbers clash',
    '番号の重複 {n}件',
    '번호 겹침 {n}건',
    '{n} numéros en double',
    '编号重复 {n} 项',
  ),
  createNew('Create new', '新規作成', '새로 만들기', 'Créer', '新建'),
  createNamed(
    'Create “{name}”',
    '「{name}」を新規作成',
    '「{name}」 새로 만들기',
    'Créer « {name} »',
    '新建“{name}”',
  ),
  cancel('Cancel', 'キャンセル', '취소', 'Annuler', '取消'),
  ok('OK', 'OK', '확인', 'OK', '确定'),

  // Statistics.
  bDay('Day', '日', '일', 'Jour', '日'),
  bWeek('Week', '週', '주', 'Semaine', '周'),
  bMonth('Month', '月', '월', 'Mois', '月'),
  range4w('4 weeks', '4週間', '4주', '4 semaines', '4周'),
  range3m('3 months', '3か月', '3달', '3 mois', '3个月'),
  range12m('12 months', '12か月', '12달', '12 mois', '12个月'),
  kHanded('Submitted', '提出', '제출', 'Remis', '已提交'),
  kWorked('Work time', '作業時間', '작업 시간', 'Temps de travail', '工作时间'),
  kPerCut('Time per cut', 'cut あたり', 'cut 당 시간', 'Temps par cut', '每 cut 用时'),
  kHourly('Hourly', '時給換算', '시급 환산', 'Taux horaire', '折合时薪'),
  kOnTime('On time', '締切遵守', '마감 준수', "À l'heure", '按时率'),
  kFirstDue('vs 1st deadline', '1次締切基準', '1차 마감 기준', '1re échéance', '按第1次截止'),
  kRetake('Retakes', 'リテイク率', '리테이크율', 'Retakes', '返修率'),
  kEarned('Earned', '金額(提出)', '금액 (제출)', 'Gagné', '金额(提交)'),
  perDayAvg('{v}/day', '1日 {v}', '하루 {v}', '{v}/jour', '每天 {v}'),
  vsPrev('vs prev.', '前期比', '지난 기간', 'vs préc.', '较上期'),
  lateN('{n} late', '遅れ {n}', '지연 {n}', '{n} en retard', '逾期 {n}'),
  hours('{n}h', '{n}時間', '{n}시간', '{n} h', '{n}小时'),
  minutes('{n} min', '{n}分', '{n}분', '{n} min', '{n}分钟'),
  extendedN('{n} extended', '延長 {n}', '연장 {n}', '{n} prolongés', '延期 {n}'),
  cHandedCuts('Submitted cuts', '提出 cut', '제출 cut', 'Cuts remis', '提交 cut'),
  cAvgLine(
    'dashed = average',
    '点線 = 平均',
    '점선 = 평균',
    'pointillé = moyenne',
    '虚线 = 平均',
  ),
  average('avg {v}', '平均 {v}', '평균 {v}', 'moy. {v}', '平均 {v}'),
  cPace('Pace by stage', '工程別ペース', '공정별 속도', 'Rythme par étape', '各工序速度'),
  cPaceNote(
    'cut/day · grey = all, colour = recent',
    'cut/日 · 灰 = 全期間, 色 = 最近',
    'cut/일 · 회색 = 지금까지, 색 = 최근',
    'cut/jour · gris = tout, couleur = récent',
    'cut/天 · 灰 = 全部, 彩色 = 近期',
  ),
  cWorks(
    'Progress by title',
    '作品別進捗',
    '작품별 진행',
    'Avancement par titre',
    '各作品进度',
  ),
  cWorksNote('handed / all', '提出 / 全体', '제출 / 전체', 'remis / tous', '已交 / 全部'),
  cClients('By client', '会社別', '회사별', 'Par client', '按公司'),
  cClientsNote(
    'handed · earned',
    '提出 · 金額',
    '제출 · 금액',
    'remis · gagné',
    '已交 · 金额',
  ),
  cLateness('Deadlines kept', '締切遵守', '마감 준수', 'Échéances tenues', '截止遵守'),
  cLatenessNote(
    'at hand-in, against the deadline then',
    '提出時点の締切に対して',
    '제출 때의 마감 기준',
    "à la remise, selon l'échéance d'alors",
    '按交付时的截止',
  ),
  early('Early', '前倒し', '일찍', 'En avance', '提前'),
  onDay('On the day', '当日', '당일', 'Le jour même', '当天'),
  late1('1 day late', '1日遅れ', '1일 늦음', '1 j de retard', '晚1天'),
  late2to3('2–3 days late', '2〜3日遅れ', '2~3일 늦음', '2–3 j de retard', '晚2–3天'),
  late4('4+ days late', '4日以上遅れ', '4일 이상 늦음', '4 j+ de retard', '晚4天以上'),
  noDue('No deadline', '締切なし', '마감 없음', 'Sans échéance', '无截止'),
  cTakes('Takes', 'テイク分布', '테이크 분포', 'Prises', '版本分布'),
  cHeat('When you work', '作業時間帯', '작업 시간대', 'Quand vous travaillez', '工作时段'),
  cHeatNote('weekday × hour', '曜日 × 時間', '요일 × 시간', 'jour × heure', '星期 × 小时'),
  cLanes('Parallel work', '並行作業', '병행 사용', 'Travail en parallèle', '并行工作'),
  cLanesNote(
    'line = worked, faint = planned',
    '線 = 実作業, 薄い = 予定',
    '선 = 실제, 옅은 = 계획',
    'ligne = réel, clair = prévu',
    '线 = 实际, 浅色 = 计划',
  ),
  lanesN('parallel {n}', '並行数 {n}', '병행 수 {n}', 'parallèle {n}', '并行数 {n}'),
  noData(
    'No data in this range',
    'この期間のデータなし',
    '이 기간 기록 없음',
    'Aucune donnée sur cette période',
    '此期间无数据',
  ),

  zoomDrag(
    'Drag sideways to zoom',
    '左右にドラッグでズーム',
    '좌우로 끌어 확대·축소',
    'Glisser pour zoomer',
    '左右拖动缩放',
  ),

  backToWork(
    'Back to in progress',
    '作業中に戻す',
    '작업중으로 되돌리기',
    'Revenir à en cours',
    '退回进行中',
  ),
  editTime('Recorded time', '記録時間', '기록한 시간', 'Temps relevé', '记录时间'),
  timeOverlap(
    'Overlaps another stretch',
    '他の記録と重なります',
    '다른 기록과 겹침',
    'Chevauche un autre relevé',
    '与其他记录重叠',
  ),
  timeInvalid(
    'The end must come after the start, and not in the future',
    '終わりは始まりの後、未来でないこと',
    '끝은 시작 뒤, 미래가 아니어야 함',
    'La fin doit suivre le début, sans être future',
    '结束须晚于开始且不在未来',
  ),
  timeStart('Started', '開始', '시작', 'Début', '开始'),
  timeStop('Stopped', '終了', '끝', 'Fin', '结束'),

  charDesign('Char. design', 'キャラデザ', '캐릭터디자인', 'Chara design', '角色设计'),

  notation('Notation', '表記', '표기', 'Notation', '标记'),
  cutNotation('Cut numbers', 'カット番号', '컷 표기', 'Numéros de cut', 'cut 编号'),
  episodeNotation(
    'Episode numbers',
    '話数',
    '화수 표기',
    "Numéros d'épisode",
    '集数编号',
  ),
  prefixNone('None', 'なし', '없음', 'Aucun', '无'),
  prefixCustom('Your own', '自由入力', '직접 입력', 'Personnalisé', '自定义'),
  digitsN('{n} digits', '{n}桁', '{n}자리', '{n} chiffres', '{n}位'),

  // Date picker headings: what is being picked.
  pickDue('Deadline', '締切日', '마감 날짜', 'Échéance', '截止日期'),
  pickKickoff('Start date', '着手日', '착수일', 'Date de début', '开工日期'),
  pickPlanStart('Work starts', '作業開始日', '작업 시작', 'Début du travail', '开始工作'),
  pickPlanEnd('Work ends', '作業終了日', '작업 끝', 'Fin du travail', '结束工作'),
  pickHoldUntil('Expected back', '待ち明け予定', '대기 예상일', 'Retour prévu', '预计恢复'),

  // On hold (waiting on someone else's material).
  hold('On hold', '待ち', '대기', 'En attente', '等待'),
  unhold('Resume', '待ち解除', '대기 해제', 'Reprendre', '解除等待'),
  holdReason('Reason', '理由', '사유', 'Motif', '原因'),
  holdExpected('Expected', '見込み', '예상일', 'Prévu', '预计'),
  inHand('{n} in hand', '手持ち {n}', '보유 {n}', '{n} en main', '在手 {n}'),
  onHold('{n} on hold', '待ち {n}', '대기 {n}', '{n} en attente', '等待 {n}'),

  // Taken off the user (work moved to someone else, 引き上げ).
  dropped('Pulled', '引き上げ', '빠짐', 'Retiré', '收回'),
  undoDrop('Undo', '元に戻す', '되돌리기', 'Annuler', '撤销'),
  showDropped(
    'Show pulled',
    '引き上げも表示',
    '빠진 것도 보기',
    'Afficher retirés',
    '显示已收回',
  ),

  // Editing a picked bundle (work, episode, part) and adding cuts to it.
  edit('Edit', '編集', '편집', 'Modifier', '编辑'),
  subtitle('Subtitle', 'サブタイトル', '부제', 'Sous-titre', '副标题'),
  editWorkWide(
    'Title and client apply to every episode of the title.',
    '作品名と会社は、その作品の全話に適用されます。',
    '작품 이름과 회사는 그 작품의 모든 화에 적용돼요.',
    'Le titre et le client valent pour tous ses épisodes.',
    '作品名和公司适用于该作品的所有集数。',
  ),
  cutsTaken(
    'Already there: {names}',
    'すでにあります：{names}',
    '이미 있음: {names}',
    'Déjà là : {names}',
    '已存在：{names}',
  ),

  // Undo and redo of the document's writes, and their keys.
  undo('Undo', '元に戻す', '실행 취소', 'Annuler', '撤销'),
  redo('Redo', 'やり直す', '다시 실행', 'Rétablir', '重做'),
  shortcuts('Shortcuts', 'ショートカット', '단축키', 'Raccourcis', '快捷键'),
  pressKeys(
    'Press keys…',
    'キーを押してください…',
    '키를 누르세요…',
    'Appuyez sur des touches…',
    '请按键…',
  ),
  keysDefault('Default', '既定', '기본값', 'Par défaut', '默认'),

  // Put away (보관) and deleted for good (완전 삭제).
  archive('Archive', 'アーカイブ', '보관', 'Archiver', '归档'),
  unarchive('Unarchive', 'アーカイブ解除', '되돌리기', 'Désarchiver', '取消归档'),
  showArchived(
    'Show archived',
    'アーカイブも表示',
    '보관한 것 보기',
    'Afficher archivés',
    '显示已归档',
  ),
  deleteForever('Delete', '完全に削除', '완전 삭제', 'Supprimer', '彻底删除'),
  deleteAsk(
    'Delete for good?',
    '完全に削除しますか？',
    '완전히 삭제할까요?',
    'Supprimer définitivement ?',
    '要彻底删除吗？',
  ),
  deleteCuts('{n} cuts', 'カット {n}', '컷 {n}', '{n} plans', '镜头 {n}'),
  deleteEpisodes('{n} episodes', '話数 {n}', '화 {n}', '{n} épisodes', '集数 {n}'),
  deleteWorks('{n} titles', '作品 {n}', '작품 {n}', '{n} titres', '作品 {n}'),
  deleteTime(
    'Timer time {t} goes too',
    '作業時間 {t} も消えます',
    '작업 시간 {t}도 지워짐',
    'Le temps chronométré {t} aussi',
    '计时 {t} 也会删除',
  ),
  deleteFinal(
    'This cannot be undone.',
    '元に戻せません。',
    '되돌릴 수 없습니다.',
    'Action irréversible.',
    '无法撤销。',
  ),
  restoreBlocked(
    'Cannot unarchive: the same cut and stage is in work again.',
    '戻せません：同じカット・工程の作業がすでにあります。',
    '되돌릴 수 없음: 같은 컷·공정의 작업이 이미 있어요.',
    'Impossible : ce plan et cette étape sont déjà repris.',
    '无法取消归档：相同镜头和工序已有任务。',
  ),

  // Deadline rounds (1st, 2nd … extensions).
  dueRound('Round {n}', '{n}次', '{n}차', '{n}e échéance', '第{n}次'),
  dueRounds('Deadlines', '締切履歴', '마감 차수', 'Échéances', '截止记录');

  const S(this.en, this.ja, this.ko, this.fr, this.zh);

  final String en;
  final String ja;
  final String ko;
  final String fr;
  final String zh;

  /// In the current [appLang].
  String get t => of(appLang.value);

  String of(Lang l) => switch (l) {
    Lang.en => en,
    Lang.ja => ja,
    Lang.ko => ko,
    Lang.fr => fr,
    Lang.zhHans => zh,
  };

  /// [t] with each `{key}` replaced by its value.
  String f(Map<String, Object?> values) {
    var s = t;
    values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

/// Short weekday names, Monday first.
List<String> weekdayNames([Lang? lang]) => switch (lang ?? appLang.value) {
  Lang.en => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  Lang.ja => const ['月', '火', '水', '木', '金', '土', '日'],
  Lang.ko => const ['월', '화', '수', '목', '금', '토', '일'],
  Lang.fr => const ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'],
  Lang.zhHans => const ['一', '二', '三', '四', '五', '六', '日'],
};

/// The month as a chart header shows it: 「11月」, 「Nov」.
String monthName(int month, [Lang? lang]) {
  final l = lang ?? appLang.value;
  return switch (l) {
    Lang.en => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1],
    Lang.fr => const [
      'janv',
      'févr',
      'mars',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sept',
      'oct',
      'nov',
      'déc',
    ][month - 1],
    _ => S.monthLabel.of(l).replaceAll('{m}', '$month'),
  };
}
