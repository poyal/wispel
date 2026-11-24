# 시험 실행

- Windows에서 `dotnet test qa/server/Wispel.Tests.csproj`로 SQLite·등록·전달·재시작·만료 시험을 실행합니다.
- Android SDK와 Java 17을 준비하고 `android-phone`에서 `gradlew testDebugUnitTest assembleDebug`를 실행합니다. 폰 에뮬레이터 한 대를 선택해 `gradlew connectedDebugAndroidTest`를 실행합니다.
- Mac의 `ios-phone`에서 `swift test`와 `xcodebuild -scheme Wispel -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO test`를 실행합니다. 실시간 전달 UI 시험에는 테스트 Windows 서버가 발행한 5분짜리 보내기 QR 주소를 `TEST_RUNNER_WISPEL_QA_INVITE`로 전달합니다.
- 앱에서 QR 등록 → 역할 확인 → 직접 수신 켜기(Android) → 시험 알림 보내기(iOS)를 실행합니다. 점검 웹의 이벤트와 Android 시스템 알림의 발신 기기·종류를 대조합니다. 워치 표시는 별도로 관찰합니다.

## 격리된 Windows 서비스에서 반복하기

`Install-Wispel.ps1 -ServiceName WispelQA`로 빈 시험 환경을 준비합니다. `WISPEL_QA_HOME`에는 시험 데이터 폴더를, `WISPEL_QA_EXE`에는 게시한 실행 파일을, `WISPEL_QA_CA`에는 서버 인증서의 공개 PEM 파일을 지정합니다. 운영 기기 대신 시험 에뮬레이터를 등록합니다.

| 시험 | 실행 및 관찰 |
|---|---|
| 6종·중복·권한 | Android 직접 수신을 켜고 `node qa/relay-live.mjs attach`를 실행합니다. 각 이벤트의 Android 확인까지 기다립니다. |
| 연속 도착 | `node qa/relay-live.mjs soak 120 750`이 건마다 확인 응답을 기다린 뒤 750ms 간격으로 다음 이벤트를 보냅니다. |
| 설정 | WispelPhone AVD에서 최근 알림 화면을 열고 `qa/Test-AndroidSettings.ps1 -Adb <adb.exe>`를 실행합니다. OS에 게시된 알림과 워치 전달 플래그를 조회합니다. |
| 실제 문자 재게시 | Android를 발신기로 재등록하고 알림 접근을 켠 뒤 `qa/Test-AndroidSms.ps1 -Adb <adb.exe>`를 실행합니다. 같은 번호의 같은 문자 두 건을 주입하고 이전 대화 갱신이 별도 이벤트가 되는지 확인합니다. |
| 시안 대조 | 기록 전체 삭제 후 `node qa/relay-live.mjs seed`를 실행합니다. 실제 보관함 단축어를 이용할 때는 격리된 서버에 iOS 발신기 한 대와 Android 본폰을 등록하고 `qa/Test-IosMosaic.ps1 -Mac <SSH별칭> -Simulator <UDID> -Adb <adb.exe>`를 실행합니다. 이 시험은 본폰 시험 기록을 비우고 카카오톡 3, 부재중 1, Slack 2, 메일 1, 문자 1건을 확인한 뒤 두 화면을 저장합니다. |
| 단축어 가져오기·실행 | 전용 Mac 시험 폴더에 `ios-phone/`을 복사하고 `Derived/`에 빌드합니다. 아이폰을 발신기로 등록한 뒤 `bash qa/ios-shortcuts.sh <UDID> "<시뮬레이터 나의 iPhone 파일 저장 폴더>"`를 실행합니다. 파일 앱을 통해 단축어를 가져오고 단축어 앱에서 실행합니다. Windows에서 해당 iOS 기기의 종류·건수와 본폰 확인을 대조합니다. 카카오톡 한 건은 파일 이름을 Wispel-Kakao로 준비해 같은 UI 시험을 실행합니다. |
| iOS 발송 대기 | 등록된 아이폰과 Android 본폰을 준비합니다. 서버 중지 후 `TEST_RUNNER_WISPEL_QA_OFFLINE=1`로 `testQueueWhileOffline`을 실행합니다. 서비스 재시작 후 아이폰 앱을 다시 열고 같은 발신기에서 카카오톡 한 건만 수신 확인됐는지 봅니다. |
| 역방향 푸시 | Android의 시험 입력을 실제 리스너에서 접수한 뒤 `qa/apple-simulator` 도구로 그 이벤트의 APNs JSON을 만듭니다. 아이폰을 본폰으로 등록한 시뮬레이터에서 `xcrun simctl push <UDID> app.wispel.phone <파일.apns>`로 주입하고 배너와 확인을 대조합니다. |
| 점검 웹 | 시험 전용 점검 주소를 로컬 파일에 보관하고 `node qa/diagnostics-browser.cjs <주소파일>`을 실행합니다. 기본 브라우저는 Windows Chrome이며 `WISPEL_QA_CHROME`으로 경로를 바꿀 수 있습니다. |

결과 파일과 실행 중 생성된 등록 주소는 로컬 `artifacts/`에 보관합니다. 점검 주소, 등록 QR, 기기 토큰은 저장소에 올리지 않습니다. [실행 결과와 실기기 시험 범위](../planning/verification.md)

### 시뮬레이터 재시작 직후 외부 URL 실행 비교

시험 아이폰에 Wispel-Sms, Wispel-Mail, Wispel-Slack, Wispel-Call, Wispel-Kakao를 가져와 각각 한 번 실행하고 최초 권한을 허용합니다. 전화 템플릿 파일명이 다르면 `-PhoneWorkflow`에 보관함의 이름을 지정합니다. QA 서버에는 이 아이폰 한 대와 직접 수신 중인 Android 본폰 한 대를 등록합니다. Mac의 `~/Library/Developer/WispelQA/Derived`에 같은 시뮬레이터 앱 빌드를 준비하고 두 기기의 이전 발송 대기열을 비웁니다.

```powershell
.\qa\Test-IosColdStart.ps1 -Mac <SSH별칭> -Simulator <시험용UDID> -Mode Burst
.\qa\Test-IosColdStart.ps1 -Mac <SSH별칭> -Simulator <시험용UDID> -Mode WaitForAck
```

두 명령 모두 켜져 있는 시험 시뮬레이터를 재시작합니다. `Burst`는 3초 간격으로 여섯 URL을 열고 `WaitForAck`는 앞선 이벤트의 Android 수신 확인 후 다음 URL을 엽니다. 각각 새 이벤트만 종류별로 집계합니다. 하나라도 누락·중복이면 실패합니다. 원인을 대조할 때는 해당 시간대 iOS 로그의 `Shortcuts` 실행 제어기와 `BackgroundShortcutRunner`의 중지·동작 실행 시각을 함께 봅니다.

한 번의 실행 안에서 위스펠 동작을 연달아 호출하는 대조군도 있습니다. 시뮬레이터에 `Wispel-QA-DirectSix`라는 시험 단축어를 만들고 **위스펠로 알림 전달** 여섯 개를 문자, 메일, Slack, 전화, 전화, 카카오톡 순서로 배치합니다. 첫 전화에는 `QA incoming`, 두 번째에는 첫 줄에 `QA`, 둘째 줄에 `부재중 전화`를 입력합니다. 최초 실행 권한을 허용한 뒤 같은 명령의 `-Mode SingleWorkflow`로 확인합니다.

단축어 템플릿을 바꾸면 Mac에서 `python3 ios-phone/Tools/shortcut_templates.py <임시폴더>`로 원본을 생성합니다. 변경한 파일마다 `shortcuts sign --mode anyone --input <원본.shortcut> --output <새파일.shortcut>`을 실행하고 서명한 결과를 `ios-phone/Shortcuts/`의 해당 이름으로 복사한 뒤 가져오기와 실행을 재시험합니다. 시험용 URL의 전화 입력은 퍼센트 인코딩된 텍스트입니다. [Apple 단축어 URL 입력 규약](https://support.apple.com/guide/shortcuts/apd624386f42/ios)
