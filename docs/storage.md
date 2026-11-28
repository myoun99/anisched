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
  그 파일에 쓰고 연결. 앱 폴더에 따로 `무제.anisched` 를 두지 않는다(유저 2026-11-27).
- **열기/새로 만들기**: 행을 바꾸기 전에 안 쓴 변경은 현재 문서에 저장, 무제이거나 저장 실패면 **스냅샷**으로 남긴다.
  열기 실패(문서 아님 · 새 버전 앱의 파일 · 접근 불가)면 아무것도 바뀌지 않는다.
- **복구 스냅샷**: `recovery/<UTC ms>-<replaced|overwritten>.anisched`. 시작할 때 30일 지난 것 삭제.
  `restoreSnapshot` 은 내용을 작업 DB 에 넣고 편집으로 취급(연결된 문서에 다음 저장 때 들어감).
- **설정도 문서에 들어간다**: `settings` 표(반올림 · 하루 시작 · 쉬는 요일 · 레인 수 …)가 작업 DB 안에 있으므로
  다른 기기에서 열면 같은 설정이 따라온다. 기기별 설정은 없다 — 전부 문서에(유저 2026-11-27).
- **최근 파일**: 열기·저장한 문서 10개, 최근 순. 북마크(Apple)도 함께 기억.

## 정해진 것 (유저 2026-11-27)

- 자동 저장: 고치고 몇 초 뒤 + 앱 나갈 때. 저장 버튼 없음, 「다른 이름으로 저장」 있음.
- 충돌: 마지막에 저장한 쪽이 덮어씀. 복귀/열기 때 다른 기기가 바꿨고 로컬 변경이 없으면 다시 읽기.
- 무제 = 작업 DB 그대로. 「저장」(위치 지정) 때 그 파일로.
- 설정은 전부 문서에 들어가 기기를 따라간다 — **작업 규칙**(반올림 · 하루 시작 · 쉬는 요일 · 레인 수 · 주 시작 · 타이머 자동 시작) 얘기.
- **기기 취향은 기기에**(관제 판단, 유저에 알림): 테마(`system`/`light`/`dark`) · 언어(기기/`en`/`ja`/`ko`/`fr`/`zh-Hans`) = 앱 컨테이너 `device.json` (`services/device_settings.dart`). 문서를 다른 기기에서 열어도 그 기기 화면은 안 바뀐다.

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

## 네이티브 (2단계, ⚠️iOS · macOS · Android 는 이 환경에서 컴파일 검증 불가)

채널 `anisched/documents` 하나, 모든 플랫폼이 같은 답 모양
`{status: granted|cancelled|missing|unavailable, location?, name?, bookmark?, size?, modifiedMs?, message?}`.
Dart 쪽은 `lib/src/platform/documents.dart` (`platform` 층: services 위, ui 아래 — 위젯 import 없음).

| 메서드 | 뜻 |
|---|---|
| `pick` | 열 문서 고르기 → 위치 · 이름 · 북마크 |
| `saveAs {sourcePath, name}` | 다 쓴 staging 파일을 사용자가 고른 곳에 **놓고** 위치를 답함 (`DocumentSession.saveAsPlaced`) |
| `reopen {location, bookmark}` | 재실행 후 권한 되살리기(Apple 북마크 → 새 북마크 / Android 영구 권한 확인) |
| `stat {location}` | 크기 · 수정시각, 없으면 `missing` |
| `readInto {location, destinationPath}` | 통째 복사해 오기 |
| `replaceFrom {location, sourcePath}` | 통째 교체 |

| 플랫폼 | 구현 (Anicel `qa_storage` 에서 옮김) |
|---|---|
| iOS (`ios/Runner/AppDelegate.swift`) | `UIDocumentPicker` 열기 · **내보내기(파일을 옮김 — iOS 엔 저장 패널이 없다)**, 보안 스코프 + `.minimalBookmark`, 코디네이터 읽기(`.withoutChanges`) · 쓰기(원본 `.forMoving` + 대상 `.forReplacing`) · 메타데이터(`.immediatelyAvailableMetadataOnly`) |
| macOS (`macos/Runner/MainFlutterWindow.swift`) | `NSOpenPanel`/`NSSavePanel`(시트), 저장 패널은 **쓴 뒤에** `.withSecurityScope` 북마크 발급, 같은 코디네이터. 샌드박스가 옆 temp 를 막으면 제자리 쓰기로 물러남. 권한: `files.user-selected.read-write` · `files.bookmarks.app-scope` |
| Android (`MainActivity.kt`) | `OPEN_DOCUMENT`/`CREATE_DOCUMENT` + `takePersistableUriPermission`, 스트림 복사(`.part` → rename), 쓰기 `"wt"`→`"w"` + `ftruncate`, stat = `SIZE` + `COLUMN_LAST_MODIFIED` |
| Windows · Linux | `file_selector` 열기/저장 대화상자 + `PathDocumentFiles` |

- 문서 형식 UTI `com.myoun.anisched.document`(확장자 `anisched`)를 iOS · macOS `Info.plist` 에 내보냄.
- UI 담당 몫: `AppLifecycleListener` hide/pause → `flush()`, resume → `resume()`; `changes` 의 `content` 에 화면 전부 다시 읽기;
  `lastSaveError` 표시; 열기 = `pickDocument()` → `openDocument`, 다른 이름으로 저장 = `saveAsPlaced(placeNewDocument, name: …)`;
  최근 파일 · 스냅샷 목록 화면. 작업 DB 경로와 같은 폴더에 `DocumentSession.open(files: platformDocumentFiles())`.
- 나중에: OS 가 건네는 `.anisched`(파일 앱/Finder 에서 열기 · 파일 연결) — Anicel `handed_files.dart` 참고.

## 웹 빌드 (미리보기 · 피드백용, 유저 2026-11-28)

- **갈래는 파일 이름으로**: 기기만의 것(`dart:io` · `dart:ffi` · `dart:isolate` · 네이티브 sqlite3 · path_provider)은 `*_io.dart` 에만.
  같은 이름의 파일이 `export '…_io.dart' if (dart.library.js_interop) '…_web.dart'` 로 고른다.
  `test/architecture/web_imports_test.dart` 가 `lib/main.dart` 에서 웹 갈래를 따라가며 위 라이브러리에 닿는 파일이 0개인지 확인(래칫).
- 시작: `lib/boot.dart` → 기기 `boot_io.dart`(앱 폴더 · 백그라운드 리더 · 파일 세션) / 웹 `boot_web.dart`. `main.dart` 는 공통.
- DB: `services/sqlite_backend.dart` 한 곳. 기기 = FFI + WAL, 웹 = `web/sqlite3.wasm`(sqlite3 3.9.2, `tool/fetch_sqlite_wasm.sh` 가 해시 확인)
  + **IndexedDB** VFS(이름 `anisched`, 파일 `/anisched.db`). OPFS 가 아니라 IndexedDB 인 이유: 워커 없이 한 스레드에서 동기 API 로
  되고 모든 브라우저(사파리 포함)에 있음 — 미리보기용으로 충분. 나머지 코드는 `CommonDatabase`(`package:sqlite3/common.dart`).
- 리더: 웹은 isolate 가 없어 `SyncCatalogueReader`(같은 스레드). 기기는 그대로 백그라운드.
- 문서: 웹 = `BrowserDocumentSession`. 작업 DB 가 브라우저에 남아 그 자체가 자동 저장(`flush` = IndexedDB 에 다 썼는지 기다림).
  「다른 이름으로 저장」 = `.anisched` **다운로드**, 「열기」 = **업로드**(file_selector), 「새로」 = 빈 문서. 다른 기기 비교 · 스냅샷 없음.
  파일 사이 이동은 메모리 VFS + `copyAllRows`(ATTACH 불가) — 같은 SQL 을 기기 테스트가 확인. 보낸 뒤 고친 것이 있으면 `dirty`.
  File System Access API(받은 파일에 바로 쓰기)는 크롬 계열만이라 **나중에**.
- 기기 설정(테마 · 언어): 웹은 localStorage `anisched.device`.
- 빌드: `flutter build web --release --no-web-resources-cdn` (CanvasKit 을 빌드에 넣음 — CDN 이 막힌 곳 · 오프라인에서도 뜸).
  GitHub Pages 는 `--base-href /anisched/`. 64비트 정수 리터럴은 웹에서 컴파일 안 됨(FNV 시드는 실행 시 파싱 — 해시는 기기에서만).
