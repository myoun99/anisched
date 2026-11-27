# 저장 — 문서 파일 하나(`.anisched`)

> 다른 기기에서 같은 파일을 열어 보는 게 핵심(유저 2026-11-27). Anicel 의 의도(단일 파일 · 형제 파일 없음 ·
> 클라우드는 「읽힌다≠최신, 써졌다≠올라갔다」)를 따른다.

## 원칙

| | |
|---|---|
| 작업 DB | 앱 컨테이너의 `anisched.db` (SQLite, WAL). **문서 파일에 SQLite 를 직접 열지 않는다** — `-wal`/`-shm`/`-journal` 형제 파일 · 잦은 부분 쓰기 · 잠금이 iOS 보안 스코프와 클라우드 동기화에서 깨진다. |
| 문서 파일 | 사용자가 고른 곳의 `*.anisched` 한 개. 내용은 SQLite 파일 하나(롤백 저널 모드, `application_id = 'ANSC'`). **통째로 쓰고 통째로 읽는다.** |
| 쓰기 | `VACUUM INTO` 로 앱 컨테이너 staging 에 만든 뒤 교체(데스크톱: 옆에 temp + rename / Apple: 코디네이터 `.forReplacing` / Android: SAF 스트림 `"wt"`). |
| 읽기 | 문서를 staging 으로 통째 복사(Apple: 코디네이터 읽기 — 파일 공급자에게 최신본을 받는 유일한 방법) → 검사·마이그레이션 → 작업 DB 의 행을 한 트랜잭션에 교체. 작업 DB 파일은 바꿔치지 않으므로 백그라운드 리더 연결이 그대로 유효하다. |
| 변경 판정 | 지문 = 크기 + 수정시각 + 내용 해시(FNV-1a 64). 크기·시각이 같으면 같은 파일, 다르면 읽어서 해시로 판정(동기화 앱이 시각만 건드리는 경우). |

앱 컨테이너 배치:

```
<app support>/
  anisched.db          작업 DB (지금 그대로)
  document.json        연결된 문서 · 지문 · dirty · 최근 파일
  staging/             쓰기·읽기 중간 파일 (시작할 때 비움)
  recovery/            복구 스냅샷 (30일 뒤 삭제)
```

## 동작 (유저 결정 1–3)

- **자동 저장**: 작업 DB 에 쓰기가 생기면(update hook) dirty → 마지막 편집 **3초 뒤**(`autosaveDelay`) 문서에 씀.
  앱이 백그라운드로 가거나 닫힐 때 `flush()`. 저장 버튼 없음, 「다른 이름으로 저장」(`saveAs`) 있음.
  dirty 는 `document.json` 에 남으므로 저장 전에 앱이 죽어도 다음 실행에서 다시 저장한다(작업 DB 는 WAL 로 이미 안전).
- **충돌 = 마지막 저장이 덮어씀.** 저장할 때 원격을 확인하지 않는다.
  앱 복귀·열기 때 `resume()`:
  - 다른 기기가 바꿨고 로컬에 안 쓴 변경이 **없으면** → 다시 읽기(`RemoteReloaded`, 화면 전부 다시 읽기 신호).
  - 로컬 변경이 **있으면** → 로컬 유지, 다음 자동 저장이 덮어씀(`RemoteKeptLocal`). 덮일 상대편 판은
    **복구 스냅샷으로 보관**(이미 읽어 온 사본을 옮길 뿐이라 공짜).
  - 파일이 없어짐 → `RemoteMissing` (연결은 유지, 유저가 정함). 권한·네트워크 문제 → `RemoteUnreachable`.
- **무제**: 저장 위치를 정하기 전엔 연결된 문서 없음 = 작업 DB 가 유일한 사본. 「저장」= 위치를 고르는 `saveAs` 로
  그 파일에 쓰고 연결. (⚠️관제 확인 대기 — 앱 폴더에 따로 `무제.anisched` 를 두지 않는 쪽으로 구현했다.)
- **열기/새로 만들기**: 행을 바꾸기 전에 안 쓴 변경은 현재 문서에 저장, 무제이거나 저장 실패면 **스냅샷**으로 남긴다.
  열기 실패(문서 아님 · 새 버전 앱의 파일 · 접근 불가)면 아무것도 바뀌지 않는다.
- **복구 스냅샷**: `recovery/<UTC ms>-<replaced|overwritten>.anisched`. 시작할 때 30일 지난 것 삭제.
  `restoreSnapshot` 은 내용을 작업 DB 에 넣고 편집으로 취급(연결된 문서에 다음 저장 때 들어감).
- **설정도 문서에 들어간다**: `settings` 표(반올림 · 하루 시작 · 쉬는 요일 · 레인 수 …)가 작업 DB 안에 있으므로
  다른 기기에서 열면 같은 설정이 따라온다. (⚠️관제 확인 대기 — 기기별로 둘 설정이 있는지.)
- **최근 파일**: 열기·저장한 문서 10개, 최근 순. 북마크(Apple)도 함께 기억.

## 코드

| 파일 | 내용 |
|---|---|
| `models/document.dart` | `DocumentRef`(위치 · 이름 · 북마크) · `DocumentFingerprint` · `RecentDocument` · `touchRecent` · FNV-1a |
| `services/document_files.dart` | 플랫폼 경계 `DocumentFiles`(reopen · stat · readInto · replaceFrom) + 실경로 구현 `PathDocumentFiles` |
| `services/document_codec.dart` | `exportDocument`(isolate, VACUUM INTO) · `prepareImport`(isolate, 검사 + 마이그레이션) · `importDocumentInto` · `createEmptyDocumentSync` |
| `services/recovery_snapshots.dart` | 스냅샷 만들기 · 목록 · 30일 GC |
| `services/document_session.dart` | 위 전부를 묶는 상태 머신. 작업은 한 줄로 직렬 실행. `changes` 스트림(state / content) |

측정(36,000 태스크, 문서 4.2MB): 내보내기 60ms · 검사 37ms(둘 다 isolate) · 행 교체 250ms(메인 isolate, 열기·다시 읽기 때만).
실사용 규모는 훨씬 작다. 문제가 되면 행 교체를 별도 쓰기 연결의 isolate 로 옮긴다.

## 네이티브 범위 (다음 단계)

`DocumentFiles` 를 플랫폼별로 구현한다. Anicel(`lib/src/services/persistence/folder_grant.dart`,
`provider_documents.dart`, `ios/Runner/AppDelegate.swift`, `macos/Runner/MainFlutterWindow.swift`,
`android/.../MainActivity.kt`, 채널 `qa_storage`)에서 가져올 수 있는 것:

| 플랫폼 | 고르기 | 다시 열기 | 읽기 | 쓰기 | stat |
|---|---|---|---|---|---|
| iOS | `UIDocumentPicker` 열기 / 내보내기(Save As) — Anicel `pickFiles` · `exportFile` | 보안 스코프 북마크 — `resolveBookmark`(stale 이면 새로 발급) | `readFileCoordinated` | `replaceFileCoordinated`(`.forReplacing`) | 새로: 코디네이터 안에서 size · modificationDate |
| macOS | `NSOpenPanel` / `NSSavePanel` | 같은 북마크(앱 샌드박스) | 같음 | 같음. ⚠️샌드박스는 고른 파일 하나만 허용 → 옆에 temp 금지 | 같음 |
| Android | SAF `ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT` + `takePersistableUriPermission` | 영구 권한이 OS 에 남음(북마크 없음) | `copyDocument`(스트림 → 파일) | `writeDocument`(`"wt"` 먼저, 안 되면 `"w"`) | `describeDocument` + `COLUMN_LAST_MODIFIED` 추가 |
| Windows · Linux | 파일 대화상자 | 경로 그대로 | `PathDocumentFiles` | 옆 temp + rename(재시도) | `FileStat` |

- Apple/Android 는 Runner 안의 메서드 채널(플러그인 아님)로 Anicel 코드를 옮겨 온다.
- 데스크톱 파일 대화상자는 Anicel 처럼 `file_selector` 플러그인이 필요하다(⚠️관제 질문).
- UI 담당 몫: `AppLifecycleListener` 에서 hide/pause → `flush()`, resume → `resume()`; `changes` 의 `content` 에 화면 전부 다시 읽기;
  `lastSaveError` 표시; 최근 파일 · 다른 이름으로 저장 · 스냅샷 목록 화면.
- 나중에: OS 가 건네는 `.anisched`(파일 앱/Finder 에서 열기 · 파일 연결) — Anicel `handed_files.dart` 참고.
