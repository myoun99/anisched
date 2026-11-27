# Anisched — 작업 규칙

> 개인 애니메이터용 스케줄·정산 앱. 플랫폼은 Anicel 과 동일(Android · iOS · macOS · Windows · Linux).
> **폰 · 태블릿 · 데스크톱, 가로 · 세로 모두** — 특정 기기 우선 없음(유저 2026-11-27). 어느 기기든 단독으로 돈다.
> ⚠️짧게 유지할 것.

## 언어

대화·문서는 **한국어**. 코드·주석·커밋 메시지·PR 본문은 **영어**.

## 성능 원칙

- 로컬 우선. 저장소는 **SQLite 한 파일**(`sqlite3` FFI, WAL). 서버 없음.
- 긴 목록·타임라인은 **가상화**(보이는 행만 빌드) 또는 `CustomPainter` 한 장으로 그린다.
- 무거운 I/O·집계는 메인 isolate 밖에서.
- 상태관리 프레임워크를 들이기 전에 유저에게 묻는다.

## 의존 방향

`core` · `models` · `services` · `controllers` 는 `ui/` 와 위젯 프레임워크를 import 하지 않는다.
이 순서로 안쪽만 import 한다.

## 머지 게이트

- `flutter analyze` (인자 없이)
- `flutter test`
- 새 컨테이너에서는 먼저 `bash tool/setup_flutter.sh` (Flutter 3.47.4 설치, 1분 안팎).

## 🚨 GitHub 정지 방지 — CI 는 최소로 (Anicel 이 하루 132회 + 매일 macOS 러너 뒤 정지됐다)

- **크론 금지.** macOS·데스크톱 빌드는 유저가 말할 때만 `workflow_dispatch` 로 한 번.
- CI 는 `main` 푸시와 PR 에만 돈다 ⇒ **레인 브랜치 푸시는 CI 0회.** 그래서 작게 자주 푸시해도 된다.
- ⛔담당 세션은 **PR 을 열지 않고 `main` 에 푸시하지 않는다.**

## 세션 분담 · 착지 흐름

- **관제** = 처음 세션(`session_01XBnkMXj2A7jv6p5JsP9oUh`). 담당 = UI · 데이터.
- 담당: 자기 컨테이너에서 analyze·test 초록 → **담당당 브랜치 하나**(`work/ui` · `work/data`) 에 푸시 →
  관제에 `send_message` 로 보고(**sha 9자 · 브랜치 · 무엇이 바뀌었나 · 확인할 것**, 한국어).
- 컨테이너는 휘발성 — **커밋하지 않은 작업은 사라진다.** 작은 단위로 커밋·푸시.
- 관제: 보낸 브랜치를 `landings/<날짜>` 에 모아 analyze·test → 하루 한 번쯤 **`main` 에 패스트포워드 푸시**(CI 1회) → 담당에 알림.
  ⚠️클라우드에선 원격 브랜치 **삭제가 막혀 있다** ⇒ 브랜치를 늘리지 말고, 착지 알림을 받은 담당은 자기 브랜치를 `origin/main` 으로 되돌려(`reset --hard` + `push --force-with-lease`) 이어 쓴다.
- 유저가 정할 것(도메인 용어·공정·화면 동작)은 **추측해서 정하지 말고** 관제를 거쳐 묻는다.
