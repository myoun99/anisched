# Anisched — 작업 규칙

> 개인 애니메이터용 스케줄·정산 앱. 1차 타깃은 **갤럭시탭 단독 실행**, 플랫폼은 Anicel 과 동일
> (Android · iOS · macOS · Windows · Linux). ⚠️짧게 유지할 것.

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
