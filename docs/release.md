# 배포 (Release)

Actions ▸ **Release** ▸ Run workflow 에서 플랫폼을 골라 **손으로만** 돌린다(크론·푸시 트리거 없음 — GitHub 정지 방지).
iOS·macOS 는 각각 macOS 러너를 하나씩 쓰므로 필요할 때만 체크한다.

| 플랫폼 | 산출물 | 필요한 시크릿 |
|---|---|---|
| Android | `anisched-android` (서명된 APK) | `ANDROID_KEYSTORE_BASE64` · `ANDROID_KEYSTORE_PASSWORD` · `ANDROID_KEY_ALIAS` · `ANDROID_KEY_PASSWORD` |
| iOS | TestFlight 업로드 | `APP_STORE_CONNECT_KEY_ID` · `APP_STORE_CONNECT_ISSUER_ID` · `APP_STORE_CONNECT_PRIVATE_KEY` · `APPLE_TEAM_ID` · `MATCH_GIT_URL` · `MATCH_PASSWORD` · `MATCH_GIT_TOKEN` (· `MATCH_GIT_USER`) |
| macOS | `anisched-macos` (Developer ID 서명·공증 zip) | 위 ASC 넷 + `DEVELOPER_ID_P12` · `DEVELOPER_ID_P12_PASSWORD` |
| Windows | `anisched-windows` (zip) | 없음 |
| Linux | `anisched-linux` (tar.gz) | 없음 |

## 처음 한 번 (유저가 하는 일)

1. **Android 업로드 키** — 한 번 만들고 잃어버리지 말 것(잃으면 기존 설치를 업데이트할 수 없다).
   Anicel 업로드 키를 같이 써도 되고 새로 만들어도 된다. 키 파일·암호는 Anicel 과 같은 자격증명 폴더
   (`G:\My Drive\Creative\Coding\Anicel\app key` 옆)에 둔다. 시크릿에는 `.jks` 를 base64 로 넣는다.
2. **App Store Connect** — 새 앱 등록: 이름 `Anisched`, 번들 ID `com.myoun.anisched`, 플랫폼 iOS
   (Developer ▸ Identifiers 에 번들 ID 도 등록). API 키로는 앱 레코드를 만들 수 없다.
3. **시크릿** — anisched 리포 ▸ Settings ▸ Secrets and variables ▸ Actions 에 위 표의 값을 넣는다.
   값은 Anicel 과 **같다**(같은 팀·같은 API 키·같은 match 리포 `myoun99/anicel-certificates`·같은 `MATCH_PASSWORD`).
   `MATCH_GIT_TOKEN` 은 그 리포에 쓰기 권한이 있어야 한다(첫 실행이 이 앱의 프로파일을 만든다).
   단일행 값은 앞뒤 개행 없이.

## 알아 둘 것 (Anicel 에서 밟은 것)

- **버전은 출시 전까지 `0.1.0` 고정** — TestFlight 외부 테스트는 버전마다 첫 빌드가 심사된다. 빌드 번호만 오른다.
- 지금 레인은 **내부 테스트**(본인 기기) 기준이라 개인정보처리방침 URL 이 필요 없다. 외부 테스트(공개 링크)를 열 땐 필요.
- TestFlight 빌드는 업로드 90일 뒤 만료된다.
- 첫 iOS 서명 실행은 보통 1~2회 시행착오가 난다.
