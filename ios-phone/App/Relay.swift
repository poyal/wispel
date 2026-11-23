import CryptoKit
import Foundation
import Security

private final class PinnedSession: NSObject, URLSessionDelegate, URLSessionTaskDelegate,
  @unchecked Sendable
{
  let server: URL, pin: String
  init(_ server: URL, _ pin: String) {
    self.server = server
    self.pin = pin
  }
  func urlSession(
    _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      challenge.protectionSpace.host == server.host,
      let trust = challenge.protectionSpace.serverTrust,
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    let hash = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map {
      String(format: "%02x", $0)
    }.joined()
    SecTrustSetAnchorCertificates(trust, [leaf] as CFArray)
    SecTrustSetAnchorCertificatesOnly(trust, true)
    guard hash == pin, SecTrustEvaluateWithError(trust, nil) else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
actor Relay {
  static let shared = Relay()
  private let key: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.wispel.phone",
    kSecAttrAccount as String: "connection",
  ]
  private var busy = false
  func identity() -> Connection? {
    var q = key
    q[kSecReturnData as String] = true
    var value: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data
    else { return nil }
    return try? JSONDecoder().decode(Connection.self, from: data)
  }
  private func save(_ c: Connection) throws {
    let data = try JSONEncoder().encode(c)
    let values = [
      kSecValueData as String: data as Any,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as Any,
    ]
    let updated = SecItemUpdate(key as CFDictionary, values as CFDictionary)
    if updated == errSecItemNotFound {
      guard SecItemAdd(key.merging(values) { _, b in b } as CFDictionary, nil) == errSecSuccess
      else { throw RelayFailure.storage }
    } else if updated != errSecSuccess {
      throw RelayFailure.storage
    }
  }
  private func send(
    _ server: URL, _ pin: String, _ path: String, _ method: String, _ token: String?, _ data: Data?
  ) async throws -> Data {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 14
    let session = URLSession(
      configuration: config, delegate: PinnedSession(server, pin), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var req = URLRequest(url: server.appendingPathComponent(path))
    req.httpMethod = method
    req.httpBody = data
    if data != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let (bytes, response) = try await session.data(for: req)
    guard let h = response as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
      throw RelayFailure.server((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    return bytes
  }
  func pair(_ raw: String, name: String) async throws {
    let i = try Invite(raw)
    let previous = identity()
    let data = try JSONEncoder().encode(["code": i.code, "name": name, "platform": "ios"])
    let result = try await send(i.server, i.pin, "v1/pair", "POST", nil, data)
    let d = try JSONDecoder().decode(Identity.self, from: result)
    guard d.role == i.role else { throw RelayFailure.wrongRole }
    try save(Connection(server: i.server, pin: i.pin, device: d))
    if let old = previous, old.server == i.server, old.pin == i.pin,
      old.device.role == "send" || d.role == "send"
    {
      _ = try? await send(
        old.server, old.pin, "v1/devices/" + old.device.id, "DELETE", old.device.token, nil)
    }
  }
  func api(_ path: String, _ method: String = "GET", _ body: [String: String]? = nil) async throws
    -> Data
  {
    guard let c = identity() else { throw RelayFailure.unpaired }
    return try await send(
      c.server, c.pin, path, method, c.device.token, try body.map { try JSONEncoder().encode($0) })
  }
  func devices() async throws -> [Device] {
    try await JSONDecoder().decode([Device].self, from: api("v1/devices"))
  }
  func rename(_ name: String) async throws {
    guard var c = identity() else { throw RelayFailure.unpaired }
    _ = try await api("v1/devices/" + c.device.id, "PUT", ["name": name])
    c.device.name = name
    try save(c)
  }
  func unlink() async throws {
    guard let c = identity() else { return }
    do { _ = try await api("v1/devices/" + c.device.id, "DELETE") } catch RelayFailure.server(401)
    { /* The server has already revoked this installation. */  }
    SecItemDelete(key as CFDictionary)
    try saveQueue([])
  }
  private var file: URL {
    get throws {
      let url = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      return url.appendingPathComponent("outbox.json")
    }
  }
  private func queue() throws -> [Event] {
    let path = try file
    guard FileManager.default.fileExists(atPath: path.path) else { return [] }
    return try JSONDecoder().decode([Event].self, from: Data(contentsOf: path))
  }
  private func saveQueue(_ q: [Event]) throws {
    try JSONEncoder().encode(q).write(
      to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  func capture(_ kind: Kind, text: String = "") async throws -> Bool {
    guard let c = identity() else { throw RelayFailure.unpaired }
    guard c.device.role == "send" else { throw RelayFailure.wrongRole }
    let e = Event(
      eventId: UUID().uuidString.lowercased(), sourceId: c.device.id,
      kind: Kind.classify(kind, text: text), occurredAt: Event.now())
    var q = try queue()
    q.append(e)
    try saveQueue(q)
    do { try await flush() } catch let failure as RelayFailure {
      if case .server(let status) = failure, status >= 500 { return false }
      throw failure
    } catch is URLError { return false }
    return try !queue().contains(where: { $0.eventId == e.eventId })
  }
  func flush() async throws {
    guard !busy, let c = identity() else { return }
    if c.device.role == "receive" {
      await flushReceipts(c)
      return
    }
    busy = true
    defer { busy = false }
    var q = try queue().filter { $0.sourceId == c.device.id && $0.isLive(at: Event.now()) }
    try saveQueue(q)
    while let e = q.first {
      _ = try await send(
        c.server, c.pin, "v1/events", "POST", c.device.token, try JSONEncoder().encode(e))
      q = try queue().filter { $0.eventId != e.eventId }
      try saveQueue(q)
      UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAccepted")
    }
  }
  func acknowledge(source: String, event: String) async {
    guard let c = identity(), c.device.role == "receive" else { return }
    let key = "pendingReceipts." + c.device.id
    var records = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    records[source + "/" + event] = source
    UserDefaults.standard.set(records, forKey: key)
    await flushReceipts(c)
  }
  private func flushReceipts(_ c: Connection) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    let key = "pendingReceipts." + c.device.id
    while let (item, source) = (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?
      .first
    {
      guard let event = item.split(separator: "/").last, identity()?.device.id == c.device.id else {
        return
      }
      do {
        let body = try JSONEncoder().encode(["sourceId": source, "eventId": String(event)])
        _ = try await send(c.server, c.pin, "v1/ack", "POST", c.device.token, body)
      } catch RelayFailure.server(404) { /* Server retention elapsed. */  } catch { return }
      var records = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
      records.removeValue(forKey: item)
      UserDefaults.standard.set(records, forKey: key)
    }
  }
}
