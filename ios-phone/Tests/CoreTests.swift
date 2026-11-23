import XCTest

@testable import WispelCore

final class CoreTests: XCTestCase {
  func testCallClassification() {
    XCTAssertEqual(Kind.classify(.call, text: "이름\r\n부재중 전화\n"), .missedCall)
    for s in ["부재중 전화 안내", "이름\n통화 종료", ""] { XCTAssertEqual(Kind.classify(.call, text: s), .call) }
    XCTAssertEqual(Kind.classify(.sms, text: "부재중 전화"), .sms)
  }
  func testWirePrivacyAndExpiry() throws {
    for k in Kind.allCases {
      let e = Event(eventId: UUID().uuidString, sourceId: "source", kind: k, occurredAt: 42)
      let data = try JSONEncoder().encode(e)
      let map = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      XCTAssertEqual(Set(map.keys), ["eventId", "sourceId", "kind", "occurredAt"])
      XCTAssertTrue(e.isLive(at: 42 + Event.day - 1))
      XCTAssertFalse(e.isLive(at: 42 + Event.day))
    }
  }
  func testEnrollmentBoundary() throws {
    let hex = String(repeating: "a", count: 64)
    let raw =
      "wispel://pair?server=https%3A%2F%2F192.168.0.7%3A7443&pin=\(hex)&role=send&code=\(hex)"
    XCTAssertEqual(try Invite(raw).role, "send")
    for bad in [
      raw.replacingOccurrences(of: "https", with: "http"),
      raw.replacingOccurrences(of: "send", with: "admin"),
    ] { XCTAssertThrowsError(try Invite(bad)) }
  }
}
