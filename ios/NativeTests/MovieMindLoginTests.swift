import Foundation
import XCTest

@testable import TogetherPoC

private final class MovieMindFixtureStorage: MovieMindSessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var token = "old-fixture-session"
  var rejectedCode: Int32?
  func read() -> String {
    lock.lock()
    defer { lock.unlock() }
    return token
  }
  func write(_ token: String) throws {
    lock.lock()
    defer { lock.unlock() }
    if let rejectedCode { throw MovieMindLoginFailure.sessionStorage(rejectedCode) }
    self.token = token
  }
}

private final class MovieMindLoginProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handler!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

final class MovieMindLoginTests: XCTestCase {
  private var suite = ""
  private var defaults: UserDefaults!
  private var directory: URL!
  override func setUpWithError() throws {
    suite = "MovieMindLoginTests." + UUID().uuidString
    defaults = UserDefaults(suiteName: suite)!
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defaults.set("https://fixture.invalid", forKey: "movieMind.origin")
    defaults.set("old-fixture-user", forKey: "movieMind.userId")
  }
  override func tearDownWithError() throws {
    MovieMindLoginProtocol.handler = nil
    defaults.removePersistentDomain(forName: suite)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
  private func transport(_ storage: MovieMindFixtureStorage) -> MovieMindTransport {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MovieMindLoginProtocol.self]
    return MovieMindTransport(
      report: { _, _ in }, configuration: config, defaults: defaults,
      directory: directory, sessionStorage: storage)
  }
  private func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
  }
  private func requestBody(_ request: URLRequest) throws -> [String: String] {
    var body = request.httpBody ?? Data()
    if body.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 1024)
      while true {
        let n = stream.read(&buffer, maxLength: buffer.count)
        if n == 0 { break }
        guard n > 0, body.count + n < 4096 else { throw URLError(.badServerResponse) }
        body.append(contentsOf: buffer.prefix(n))
      }
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
  }
  private func pending() throws -> Data {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let row = MovieMindPending(
      id: "pending-fixture", path: "records/manual:fixture", body: try json(["rating": 7]),
      method: "PUT", conflict: false, movieId: "manual:fixture")
    let data = try JSONEncoder().encode([row])
    try data.write(to: directory.appendingPathComponent("outbox.json"))
    return data
  }

  func testAddressNormalizationKeepsTheServiceBoundary() throws {
    XCTAssertEqual(
      try MovieMindLoginFailure.canonicalOrigin(" \nHTTPS://Fixture.Invalid:443/\n "),
      "https://fixture.invalid")
    XCTAssertEqual(
      try MovieMindLoginFailure.canonicalOrigin("http://127.0.0.1:8091/"), "http://127.0.0.1:8091")
    for value in [
      "http://fixture.invalid", "https://fixture.invalid/api", "https://u:p@fixture.invalid",
      "https://fixture.invalid/?token=x", "https://fixture.invalid/#x", "not an address",
    ] {
      XCTAssertThrowsError(try MovieMindLoginFailure.canonicalOrigin(value))
    }
  }
  func testNativeLoginUsesItsOwnBudgetAndBackgroundRequestsStayShort() async throws {
    let storage = MovieMindFixtureStorage()
    var paths = [String]()
    MovieMindLoginProtocol.handler = { request in
      paths.append(request.url!.path)
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-MovieMind-Client"), "native")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-MovieMind"), "1")
      if request.url!.path == "/api/auth/login" {
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-MovieMind-Account"))
        let body = try self.requestBody(request)
        XCTAssertEqual(body["name"], "fixture_user")
        XCTAssertEqual(body["password"], " fixture-password ")
        return (200, try self.json(["token": "new-fixture-session", "userId": "new-fixture-user"]))
      }
      XCTAssertEqual(request.timeoutInterval, 3)
      XCTAssertEqual(
        request.value(forHTTPHeaderField: "Authorization"), "Bearer new-fixture-session")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-MovieMind-Account"), "new-fixture-user")
      return (200, try self.json([]))
    }
    let client = transport(storage)
    try await client.login(
      origin: " \nhttps://fixture.invalid/ ", name: " fixture_user ", password: " fixture-password "
    )
    _ = try await client.request("movies")
    XCTAssertEqual(paths, ["/api/auth/login", "/api/movies"])
    XCTAssertEqual(
      MovieMindStoredSession.decode(
        storage.read(), origin: "https://fixture.invalid", userId: "new-fixture-user"),
      "new-fixture-session")
    XCTAssertEqual(defaults.string(forKey: "movieMind.origin"), "https://fixture.invalid")
    XCTAssertEqual(defaults.string(forKey: "movieMind.userId"), "new-fixture-user")
  }
  func testServerRejectionKeepsOriginalSessionAndShowsStatus() async throws {
    let storage = MovieMindFixtureStorage()
    MovieMindLoginProtocol.handler = { _ in (403, try self.json(["error": "rejected"])) }
    do {
      try await transport(storage).login(
        origin: "https://fixture.invalid", name: "fixture_user", password: "fixture-password")
      XCTFail("Rejected login must fail")
    } catch { XCTAssertTrue(MovieMindLoginFailure.message(for: error).contains("HTTP 403")) }
    XCTAssertEqual(storage.read(), "old-fixture-session")
    XCTAssertEqual(defaults.string(forKey: "movieMind.userId"), "old-fixture-user")
  }
  func testSecureStorageFailureRevokesOnlyNewReceiptAndPreservesOldState() async throws {
    let storage = MovieMindFixtureStorage()
    storage.rejectedCode = -34018
    var logout = false
    MovieMindLoginProtocol.handler = { request in
      if request.url!.path == "/api/auth/logout" {
        logout = true
        XCTAssertEqual(
          request.value(forHTTPHeaderField: "Authorization"), "Bearer rejected-new-session")
        XCTAssertEqual(request.timeoutInterval, 3)
        return (200, try self.json(["ok": true]))
      }
      return (200, try self.json(["token": "rejected-new-session", "userId": "new-fixture-user"]))
    }
    do {
      try await transport(storage).login(
        origin: "https://fixture.invalid", name: "fixture_user", password: "fixture-password")
      XCTFail("Storage rejection must fail login")
    } catch { XCTAssertTrue(MovieMindLoginFailure.message(for: error).contains("-34018")) }
    XCTAssertTrue(logout)
    XCTAssertEqual(storage.read(), "old-fixture-session")
    XCTAssertEqual(defaults.string(forKey: "movieMind.userId"), "old-fixture-user")
  }
  func testUnreadableQueueCannotBeBypassedByTryingLoginAgain() async throws {
    let storage = MovieMindFixtureStorage()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("outbox.json")
    let original = Data("unreadable-fixture".utf8)
    try original.write(to: file)
    MovieMindLoginProtocol.handler = { _ in
      XCTFail("Unreadable drafts must block authentication")
      return (500, Data())
    }
    let client = transport(storage)
    for _ in 0..<2 {
      do {
        try await client.login(
          origin: "https://fixture.invalid", name: "fixture_user", password: "fixture-password")
        XCTFail("Unreadable queue must remain protected")
      } catch { XCTAssertTrue(MovieMindLoginFailure.message(for: error).contains("待同步文件")) }
    }
    XCTAssertEqual(try Data(contentsOf: file), original)
    XCTAssertEqual(storage.read(), "old-fixture-session")
  }
  func testPendingDraftsBlockChangingServiceBeforeSendingCredentials() async throws {
    let storage = MovieMindFixtureStorage()
    let original = try pending()
    MovieMindLoginProtocol.handler = { _ in
      XCTFail("Other-service login must not be sent")
      return (500, Data())
    }
    do {
      try await transport(storage).login(
        origin: "https://other.invalid", name: "fixture_user", password: "fixture-password")
      XCTFail("A different service must not receive pending drafts")
    } catch { XCTAssertTrue(MovieMindLoginFailure.message(for: error).contains("原服务")) }
    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("outbox.json")), original)
    XCTAssertEqual(storage.read(), "old-fixture-session")
  }
  func testPendingDraftsBlockChangingAccountAfterServerAcceptance() async throws {
    let storage = MovieMindFixtureStorage()
    let original = try pending()
    var logout = false
    MovieMindLoginProtocol.handler = { request in
      if request.url!.path == "/api/auth/logout" {
        logout = true
        return (200, try self.json(["ok": true]))
      }
      return (200, try self.json(["token": "other-account-session", "userId": "other-user"]))
    }
    do {
      try await transport(storage).login(
        origin: "https://fixture.invalid", name: "fixture_user", password: "fixture-password")
      XCTFail("A different account must not acquire pending drafts")
    } catch { XCTAssertTrue(MovieMindLoginFailure.message(for: error).contains("原账号")) }
    XCTAssertTrue(logout)
    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("outbox.json")), original)
    XCTAssertEqual(defaults.string(forKey: "movieMind.userId"), "old-fixture-user")
  }
  func testFailureMessagesClassifyWithoutEchoingCredentials() {
    let hidden = "private-fixture-password-and-token"
    for code in [403, 429, 503, 302] {
      let error = NSError(
        domain: "MovieMindHTTP", code: code, userInfo: [NSLocalizedDescriptionKey: hidden])
      let message = MovieMindLoginFailure.message(for: error)
      XCTAssertTrue(message.contains("HTTP \(code)"))
      XCTAssertFalse(message.contains(hidden))
    }
    XCTAssertTrue(MovieMindLoginFailure.message(for: URLError(.timedOut)).contains("-1001"))
    XCTAssertTrue(MovieMindLoginFailure.message(for: URLError(.cannotFindHost)).contains("解析"))
    XCTAssertTrue(
      MovieMindLoginFailure.message(for: URLError(.serverCertificateUntrusted)).contains("HTTPS"))
    XCTAssertFalse(
      MovieMindLoginFailure.message(
        for: NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: hidden])
      ).contains(hidden))
  }

  func testStoredReceiptCannotCrossAccountOrService() throws {
    let receipt = MovieMindStoredSession(
      origin: "https://fixture.invalid", userId: "fixture-user", token: "fixture-private-session")
    let value = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
    XCTAssertEqual(
      MovieMindStoredSession.decode(value, origin: receipt.origin, userId: receipt.userId),
      receipt.token)
    XCTAssertEqual(
      MovieMindStoredSession.decode(value, origin: "https://other.invalid", userId: receipt.userId),
      "")
    XCTAssertEqual(
      MovieMindStoredSession.decode(value, origin: receipt.origin, userId: "other-user"), "")
    XCTAssertEqual(
      MovieMindStoredSession.decode(
        "{broken-secret-envelope", origin: receipt.origin, userId: receipt.userId), "")
  }

  func testExplicitTemporaryLoginWorksWithoutSavingReceiptAndCannotReuseOldKeychainAfterRelaunch()
    async throws
  {
    let storage = MovieMindFixtureStorage()
    storage.rejectedCode = -34018
    var authorization = [String?]()
    MovieMindLoginProtocol.handler = { request in
      if request.url!.path == "/api/auth/login" {
        return (
          200, try self.json(["token": "temporary-fixture-session", "userId": "temporary-user"])
        )
      }
      authorization.append(request.value(forHTTPHeaderField: "Authorization"))
      if request.value(forHTTPHeaderField: "Authorization") == nil {
        return (401, try self.json(["error": "login required"]))
      }
      return (200, try self.json([]))
    }
    let client = transport(storage)
    try await client.login(
      origin: "https://fixture.invalid", name: "fixture_user", password: "fixture-password",
      persistent: false)
    XCTAssertEqual(storage.read(), "old-fixture-session")
    XCTAssertTrue(defaults.bool(forKey: "movieMind.transientSession"))
    _ = try await client.request("movies")
    let relaunched = transport(storage)
    do {
      _ = try await relaunched.request("movies")
      XCTFail("Temporary login must require reauthentication after process loss")
    } catch { XCTAssertTrue(MovieMindLoginFailure.message(for: error).contains("HTTP 401")) }
    XCTAssertEqual(authorization.count, 2)
    XCTAssertEqual(authorization[0], "Bearer temporary-fixture-session")
    XCTAssertNil(authorization[1])
  }
  func testNativeJournalCannotSendFromAnOldAccountScreen() async throws {
    let storage = MovieMindFixtureStorage()
    var count = 0
    MovieMindLoginProtocol.handler = { _ in
      count += 1
      return (200, try self.json([]))
    }
    let client = transport(storage)
    let scope = MovieMindScope(origin: "https://fixture.invalid", account: "old-fixture-user")
    _ = try await client.scopedRequest("records", scope: scope)
    defaults.set("other-fixture-user", forKey: "movieMind.userId")
    do {
      _ = try await client.scopedRequest("records", scope: scope)
      XCTFail("An old screen cannot read the new account")
    } catch { XCTAssertTrue(error is MovieMindJournalFailure) }
    XCTAssertEqual(count, 1)
  }

  func testManualJournalPersistsAndRetriesWithSameMutationWhenPlaybackHooksAreOff() async throws {
    let storage = MovieMindFixtureStorage()
    var mutations = [String]()
    var accept = false
    MovieMindLoginProtocol.handler = { request in
      let body = try self.requestBodyAny(request)
      let id = try XCTUnwrap(body["mutationId"] as? String)
      mutations.append(id)
      if !accept { return (503, try self.json(["error": "fixture outage"])) }
      return (200, try self.json(["mutationId": id, "movieId": "tmdb:100", "revision": 1]))
    }
    let data = try MovieMindJournal.recordBody(
      movie: "tmdb:100", original: [:], status: "seen", rating: nil,
      comment: "fixture only", date: "", together: false, likes: "", dislikes: "", experience: "",
      favorite: false, sharedWish: false)
    let first = transport(storage)
    await first.configure(enabled: false, watch: false, rating: false)
    let queued = await first.enqueue(
      path: "records/tmdb:100", body: data, method: "PUT",
      account: "old-fixture-user", origin: "https://fixture.invalid", userInitiated: true)
    XCTAssertTrue(queued)
    let retained = try await JSONDecoder().decode([MovieMindPending].self, from: first.drafts())
    XCTAssertEqual(retained.count, 1)
    XCTAssertEqual(retained.first?.userInitiated, true)
    accept = true
    let second = transport(storage)
    await second.configure(enabled: false, watch: false, rating: false)
    await second.flush()
    let remaining = try await JSONDecoder().decode([MovieMindPending].self, from: second.drafts())
    XCTAssertTrue(remaining.isEmpty)
    XCTAssertEqual(mutations.count, 2)
    XCTAssertEqual(mutations.first, mutations.last)
  }

  private func requestBodyAny(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 2048)
      while true {
        let n = stream.read(&buffer, maxLength: buffer.count)
        if n == 0 { break }
        guard n > 0, data.count + n < 65536 else { throw URLError(.badServerResponse) }
        data.append(contentsOf: buffer.prefix(n))
      }
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

}
