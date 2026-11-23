import XCTest

final class WispelUITests: XCTestCase {
  func testRunImportedShortcut() throws {
    guard ProcessInfo.processInfo.environment["WISPEL_QA_RUN_SHORTCUT"] == "1" else {
      throw XCTSkip("Requires the imported Wispel-Kakao workflow and a paired sender")
    }
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    let deadline = Date().addingTimeInterval(12)
    while Date() < deadline {
      for app in [system, shortcuts] {
        for label in ["Allow", "허용", "항상 허용", "Always Allow"] {
          let button = app.buttons[label].firstMatch
          if button.exists && button.isHittable { button.tap(); return }
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }
    XCTAssertTrue(shortcuts.state == .runningForeground)
  }
  func testQueueWhileOffline() throws {
    guard ProcessInfo.processInfo.environment["WISPEL_QA_OFFLINE"] == "1" else {
      throw XCTSkip("Requires a paired sender and stopped QA relay")
    }
    let app = XCUIApplication()
    app.launch()
    let send = app.buttons["시험 알림 보내기"]
    XCTAssertTrue(send.waitForExistence(timeout: 15))
    send.tap()
    XCTAssertTrue(app.staticTexts["발송 대기"].waitForExistence(timeout: 25))
  }
  func testImportSignedShortcut() throws {
    guard ProcessInfo.processInfo.environment["WISPEL_QA_SHORTCUT_FILE"] == "1" else {
      throw XCTSkip("Requires staged Wispel-Kakao.shortcut in On My iPhone")
    }
    let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    files.launch()
    func find(_ app: XCUIApplication, _ labels: [String]) -> XCUIElement? {
      for label in labels {
        let item = app.descendants(matching: .any).matching(
          NSPredicate(format: "label ==[c] %@", label)
        ).firstMatch
        if item.exists && item.isHittable { return item }
      }
      return nil
    }
    if let next = find(files, ["Continue", "계속"]) { next.tap() }
    if let browse = find(files, ["Browse", "둘러보기", "탐색"]) { browse.tap() }
    if let local = find(files, ["On My iPhone", "나의 iPhone", "나의 아이폰"]) { local.tap() }
    let name = ProcessInfo.processInfo.environment["WISPEL_QA_SHORTCUT_NAME"] ?? "Wispel-Kakao"
    let file = files.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS[c] %@", name)
    ).firstMatch
    guard file.waitForExistence(timeout: 7) else {
      XCTFail(files.debugDescription)
      return
    }
    file.tap()
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
      if let add = find(shortcuts, ["Add Shortcut", "단축어 추가", "Set Up Shortcut", "단축어 설정"]) {
        add.tap()
        return
      }
      if let next = find(shortcuts, ["Continue", "계속", "Open", "열기"]) { next.tap() }
      RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
    XCTFail(shortcuts.debugDescription)
  }
  func testLaunch() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.staticTexts["Wispel"].waitForExistence(timeout: 10))
  }
  func testForwardFromPhone() throws {
    guard let raw = ProcessInfo.processInfo.environment["WISPEL_QA_INVITE"] else {
      throw XCTSkip("Requires a live test server and a single-use sender invitation")
    }
    let app = XCUIApplication()
    app.launch()
    app.open(URL(string: raw)!)
    let pair = app.buttons["이 역할로 등록"]
    XCTAssertTrue(pair.waitForExistence(timeout: 8))
    pair.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for label in ["Allow", "허용"] {
      let button = system.alerts.buttons[label]
      if button.waitForExistence(timeout: 2) {
        button.tap()
        break
      }
    }
    let test = app.buttons["시험 알림 보내기"]
    XCTAssertTrue(test.waitForExistence(timeout: 18))
    test.tap()
    XCTAssertTrue(app.staticTexts["서버 접수 완료"].waitForExistence(timeout: 15))
    for label in ["전화 알림", "새 문자", "카카오톡", "Slack", "메일플러그"] {
      let get = app.buttons[label + " 단축어 받기"]
      XCTAssertTrue(get.waitForExistence(timeout: 5))
      get.tap()
      XCTAssertTrue(app.buttons["서명된 단축어 파일 받기"].waitForExistence(timeout: 5))
      app.buttons["닫기"].tap()
    }
  }
  func testReceiverSetup() throws {
    guard let raw = ProcessInfo.processInfo.environment["WISPEL_QA_RECEIVER"] else {
      throw XCTSkip("Requires a single-use iOS receiver invitation")
    }
    let app = XCUIApplication()
    app.launch()
    app.open(URL(string: raw)!)
    let pair = app.buttons["이 역할로 등록"]
    XCTAssertTrue(pair.waitForExistence(timeout: 8))
    pair.tap()
    let enable = app.buttons["수신 알림 허용"]
    XCTAssertTrue(enable.waitForExistence(timeout: 15))
    enable.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for label in ["Allow", "허용"] {
      let button = system.alerts.buttons[label]
      if button.waitForExistence(timeout: 2) {
        button.tap()
        break
      }
    }
    XCTAssertTrue(app.staticTexts["수신 권한 허용"].waitForExistence(timeout: 8))
  }
}
