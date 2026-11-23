import AppIntents

enum InputKind: String, AppEnum {
  case call, sms, kakao, slack, mail
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "알림 종류"
  static var caseDisplayRepresentations: [InputKind: DisplayRepresentation] = [
    .call: "전화", .sms: "문자", .kakao: "카카오톡", .slack: "Slack", .mail: "메일플러그",
  ]
}
struct ForwardNotice: AppIntent {
  static var title: LocalizedStringResource = "위스펠로 알림 전달"
  static var description = IntentDescription("알림 종류를 등록한 본폰에 전달합니다. 전화 문구는 이 폰 안에서만 분류합니다.")
  static var openAppWhenRun = false
  static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
  @Parameter(title: "종류") var kind: InputKind
  @Parameter(title: "전화 알림 텍스트") var text: String?
  func perform() async throws -> some IntentResult {
    _ = try await Relay.shared.capture(Kind(rawValue: kind.rawValue)!, text: text ?? "")
    return .result()
  }
}
struct WispelShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ForwardNotice(), phrases: ["\(.applicationName)로 알림 전달"], shortTitle: "알림 전달",
      systemImageName: "paperplane")
  }
}
