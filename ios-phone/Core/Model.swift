import Foundation

enum Kind: String, Codable, CaseIterable {
  case call, missedCall, sms, kakao, slack, mail
  var label: String {
    switch self {
    case .call: return "전화 알림"
    case .missedCall: return "부재중 전화"
    case .sms: return "새 문자"
    case .kakao: return "카카오톡"
    case .slack: return "Slack"
    case .mail: return "메일플러그"
    }
  }
  static func classify(_ supplied: Kind, text: String) -> Kind {
    guard supplied == .call else { return supplied }
    let last = text.split(whereSeparator: \.isNewline).last?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    return last == "부재중 전화" ? .missedCall : .call
  }
}
struct Event: Codable, Equatable {
  var eventId: String
  var sourceId: String
  var kind: Kind
  var occurredAt: Int64
  static let day: Int64 = 86_400_000
  static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
  func isLive(at time: Int64) -> Bool { occurredAt > time - Self.day }
}
struct Invite {
  let server: URL, pin: String, role: String, code: String
  init(_ raw: String) throws {
    guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      c.scheme == "wispel", c.host == "pair"
    else { throw RelayFailure.invalidInvite }
    func field(_ k: String) -> String? { c.queryItems?.first { $0.name == k }?.value }
    guard let s = field("server"), let endpoint = URLComponents(string: s),
      endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
      endpoint.password == nil, endpoint.path.isEmpty, endpoint.query == nil,
      endpoint.fragment == nil, let server = endpoint.url,
      let pin = field("pin"), let code = field("code"),
      [pin, code].allSatisfy({ $0.utf8.count == 64 && $0.allSatisfy(\.isHexDigit) }),
      let role = field("role"), ["send", "receive"].contains(role)
    else { throw RelayFailure.invalidInvite }
    self.server = server
    self.pin = pin.lowercased()
    self.code = code
    self.role = role
  }
}
enum RelayFailure: LocalizedError {
  case invalidInvite, unpaired, wrongRole
  case server(Int)
  case storage
  var errorDescription: String? {
    switch self {
    case .invalidInvite: return "등록 QR의 주소를 확인해 주세요."
    case .unpaired: return "먼저 기기를 등록해 주세요."
    case .wrongRole: return "기기 역할을 확인해 주세요."
    case .server(let s): return "서버 응답 \(s)"
    case .storage: return "기기 저장소를 열 수 없습니다."
    }
  }
}
struct Identity: Codable {
  var id: String, name: String, platform: String, role: String, token: String
}
struct Device: Codable, Identifiable {
  var id: String, name: String, platform: String, role: String
}
struct Connection: Codable { var server: URL, pin: String, device: Identity }
