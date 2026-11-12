import AVFoundation
import Combine
import Foundation
import Security

private final class MovieMindNoRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
struct MovieMindPending: Codable, Identifiable {
  let id: String
  let path: String
  var body: Data
  let method: String
  var conflict: Bool
  let movieId: String
}
enum MovieMindAcknowledgement {
  static func decode(_ data: Data, path: String, body: Data) throws -> [String: Any] {
    guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { throw URLError(.badServerResponse) }
    if path.hasPrefix("records/") {
      guard let mutation = sent["mutationId"] as? String,
        reply["mutationId"] as? String == mutation,
        let record = sent["record"] as? [String: Any],
        let movie = record["movieId"] as? String, reply["movieId"] as? String == movie,
        let revision = reply["revision"] as? Int, revision > 0
      else { throw URLError(.badServerResponse) }
    } else if path == "watch/events" {
      guard let event = sent["id"] as? String, reply["eventId"] as? String == event,
        let session = sent["sessionId"] as? String, reply["id"] as? String == session,
        let edition = sent["editionId"] as? String, reply["editionId"] as? String == edition,
        let covered = reply["coveredMs"] as? Double, covered.isFinite, covered >= 0,
        reply["possibleFinished"] is Bool
      else { throw URLError(.badServerResponse) }
    } else {
      guard reply["saved"] as? Bool == true else { throw URLError(.badServerResponse) }
    }
    return reply
  }
}
actor MovieMindTransport {
  private let directory: URL
  private let defaults: UserDefaults
  private let sessionStorage: (any MovieMindSessionStorage)?
  private var pending = [MovieMindPending]()
  private var loaded = false
  private var blocked = false
  private var flushing = false
  private var authenticating = false
  private var transientSession: MovieMindStoredSession?
  private var enabled = false
  private var watchEnabled = false
  private var ratingEnabled = true
  private let report: @Sendable (String, [String: String]?) -> Void
  private let session: URLSession
  private let loginSession: URLSession
  init(
    report: @escaping @Sendable (String, [String: String]?) -> Void,
    configuration: URLSessionConfiguration = .ephemeral,
    defaults: UserDefaults = .standard, directory: URL? = nil,
    sessionStorage: (any MovieMindSessionStorage)? = nil
  ) {
    self.report = report
    self.defaults = defaults
    self.directory =
      directory
      ?? FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
        "MovieMind", isDirectory: true)
    self.sessionStorage = sessionStorage
    let config = configuration.copy() as! URLSessionConfiguration
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.timeoutIntervalForRequest = 3
    config.timeoutIntervalForResource = 4
    session = URLSession(configuration: config, delegate: MovieMindNoRedirect(), delegateQueue: nil)
    let loginConfig = configuration.copy() as! URLSessionConfiguration
    loginConfig.httpShouldSetCookies = false
    loginConfig.httpCookieStorage = nil
    loginConfig.timeoutIntervalForRequest = 15
    loginConfig.timeoutIntervalForResource = 20
    loginSession = URLSession(
      configuration: loginConfig, delegate: MovieMindNoRedirect(), delegateQueue: nil)
  }
  private func load() throws {
    if loaded { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("outbox.json")
      if FileManager.default.fileExists(atPath: file.path) {
        let data = try Data(contentsOf: file)
        guard data.count < 8 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        pending = try JSONDecoder().decode([MovieMindPending].self, from: data)
      }
      loaded = true
      blocked = false
    } catch {
      blocked = true
      report("待同步文件无法读取，原文件已保留", nil)
      throw error
    }
  }
  private func persist() throws {
    guard !blocked else { throw URLError(.cannotWriteToFile) }
    try JSONEncoder().encode(pending).write(
      to: directory.appendingPathComponent("outbox.json"),
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  private func storedToken(origin: String) -> String {
    let owner = defaults.string(forKey: "movieMind.userId")
    guard
      (try? MovieMindLoginFailure.canonicalOrigin(
        defaults.string(forKey: "movieMind.origin") ?? "")) == origin
    else { return "" }
    if defaults.bool(forKey: "movieMind.transientSession") {
      guard let transientSession, transientSession.origin == origin,
        transientSession.userId == owner
      else { return "" }
      return transientSession.token
    }
    if let sessionStorage {
      return MovieMindStoredSession.decode(sessionStorage.read(), origin: origin, userId: owner)
    }
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MovieMind",
      kSecAttrAccount as String: "session", kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return "" }
    return MovieMindStoredSession.decode(
      String(data: data, encoding: .utf8) ?? "", origin: origin, userId: owner)
  }
  private func storeToken(_ value: String) throws {
    if let sessionStorage {
      try sessionStorage.write(value)
      return
    }
    let key: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MovieMind",
      kSecAttrAccount as String: "session",
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updated = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else {
      throw MovieMindLoginFailure.sessionStorage(updated)
    }
    var q = key
    q[kSecValueData as String] = Data(value.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(q as CFDictionary, nil)
    guard added == errSecSuccess else { throw MovieMindLoginFailure.sessionStorage(added) }
  }
  func configure(enabled: Bool, watch: Bool, rating: Bool) {
    self.enabled = enabled
    watchEnabled = watch
    ratingEnabled = rating
  }
  func request(
    _ path: String, body: Data? = nil, method: String = "GET", origin: String? = nil,
    token: String? = nil, isLogin: Bool = false
  ) async throws -> Data {
    let root = try MovieMindLoginFailure.canonicalOrigin(
      origin ?? defaults.string(forKey: "movieMind.origin") ?? "")
    guard let url = URL(string: root + "/api/" + path)
    else { throw URLError(.badURL) }
    var req = URLRequest(url: url)
    req.timeoutInterval = isLogin ? 15 : 3
    req.httpMethod = method
    req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("1", forHTTPHeaderField: "X-MovieMind")
    req.setValue("native", forHTTPHeaderField: "X-MovieMind-Client")
    if !isLogin {
      req.setValue(
        defaults.string(forKey: "movieMind.userId"), forHTTPHeaderField: "X-MovieMind-Account")
    }
    let auth = token ?? storedToken(origin: root)
    if !auth.isEmpty { req.setValue("Bearer " + auth, forHTTPHeaderField: "Authorization") }
    let (data, response) = try await (isLogin ? loginSession : session).data(for: req)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard response.statusCode >= 200, response.statusCode < 300 else {
      throw NSError(domain: "MovieMindHTTP", code: response.statusCode)
    }
    guard data.count < 2 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
    return data
  }
  func login(origin: String, name: String, password: String, persistent: Bool = true) async throws {
    guard !authenticating else { throw MovieMindLoginFailure.inProgress }
    authenticating = true
    defer { authenticating = false }
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !password.isEmpty else { throw MovieMindLoginFailure.emptyCredentials }
    let target = try MovieMindLoginFailure.canonicalOrigin(origin)
    do { try load() } catch { throw MovieMindLoginFailure.unreadableOutbox }
    let before = try? MovieMindLoginFailure.canonicalOrigin(
      defaults.string(forKey: "movieMind.origin") ?? "")
    guard pending.isEmpty || before == target else { throw MovieMindLoginFailure.pendingService }
    let data = try await request(
      "auth/login",
      body: JSONSerialization.data(withJSONObject: ["name": name, "password": password]),
      method: "POST", origin: target, token: "", isLogin: true)
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: String],
      let token = result["token"], !token.isEmpty, let user = result["userId"], !user.isEmpty
    else { throw MovieMindLoginFailure.invalidReceipt }
    do {
      guard pending.isEmpty || before == target else { throw MovieMindLoginFailure.pendingService }
      let owner = defaults.string(forKey: "movieMind.userId")
      guard pending.isEmpty || owner == user else { throw MovieMindLoginFailure.pendingAccount }
      let stored = MovieMindStoredSession(origin: target, userId: user, token: token)
      if persistent {
        let value = String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
        try storeToken(value)
        defaults.set(false, forKey: "movieMind.transientSession")
        transientSession = nil
      } else {
        // Persist only the mode/scope. A new process must never reuse an older Keychain receipt.
        defaults.set(true, forKey: "movieMind.transientSession")
        transientSession = stored
      }
    } catch {
      // Revoke only the newly issued receipt; retain the original local session and drafts.
      _ = try? await request("auth/logout", method: "POST", origin: target, token: token)
      throw error
    }
    defaults.set(target, forKey: "movieMind.origin")
    defaults.set(user, forKey: "movieMind.userId")
    report(persistent ? "已登录独立 MovieMind 账号" : "仅本次登录成功；App 重启后需重新登录", nil)
  }
  func enqueue(
    path: String, body: Data, method: String, movieId: String = "", account: String?, origin: String
  ) async -> Bool {
    guard account == defaults.string(forKey: "movieMind.userId"),
      origin == (defaults.string(forKey: "movieMind.origin") ?? "")
    else {
      report("账号或服务已改变，尚未保存；请核对原评分草稿", nil)
      return false
    }
    do {
      try load()
      guard pending.count < 1000 else {
        report("待同步队列已满，请先同步；观影记录暂不继续写入", nil)
        return false
      }
      pending.append(
        MovieMindPending(
          id: UUID().uuidString, path: path, body: body, method: method, conflict: false,
          movieId: movieId))
      try persist()
      report("已保存在本机，等待同步", nil)
      await flush()
      return true
    } catch {
      blocked = true
      report("无法保存待同步内容，原文件已保留；播放不受影响", nil)
      return false
    }
  }
  func flush() async {
    guard enabled, !flushing else { return }
    flushing = true
    defer { flushing = false }
    do {
      try load()
      for item in pending {
        if item.conflict || item.path == "watch/events" && !watchEnabled
          || item.path.hasPrefix("records/") && !ratingEnabled
        {
          continue
        }
        do {
          let data = try await request(item.path, body: item.body, method: item.method)
          let result = try MovieMindAcknowledgement.decode(data, path: item.path, body: item.body)
          pending.removeAll { $0.id == item.id }
          try persist()
          if item.path == "watch/events",
            result["possibleFinished"] as? Bool == true,
            let body = try JSONSerialization.jsonObject(with: item.body) as? [String: Any]
          {
            report(
              "可能已看完，评分可以跳过",
              ["movieId": item.movieId, "sessionId": body["sessionId"] as? String ?? ""])
          }
        } catch {
          if (error as NSError).domain == "MovieMindHTTP", (error as NSError).code == 409 {
            if let i = pending.firstIndex(where: { $0.id == item.id }) {
              pending[i].conflict = true
              try persist()
            }
            report("检测到并发编辑，草稿已保留，请核对待同步内容", nil)
          } else {
            report("暂未同步，内容已保留；播放不受影响", nil)
            return
          }
        }
      }
      report(pending.isEmpty ? "MovieMind 已同步" : "有待同步或冲突内容，请核对", nil)
    } catch { report("待同步文件已保留，请重试", nil) }
  }
  func drafts() throws -> Data {
    try load()
    return try JSONEncoder().encode(pending)
  }
  func resolve(id: String, body: Data?) async throws {
    try load()
    guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
    if let body {
      pending[i].body = body
      pending[i].conflict = false
    } else {
      pending.remove(at: i)
    }
    try persist()
    await flush()
  }
}

@MainActor final class MovieMindClient: ObservableObject {
  static let shared = MovieMindClient()
  struct Suggestion: Identifiable {
    let movieId: String
    let sessionId: String
    var id: String { sessionId }
  }
  @Published var enabled = UserDefaults.standard.bool(forKey: "movieMind.enabled") {
    didSet {
      UserDefaults.standard.set(enabled, forKey: "movieMind.enabled")
      updateFlags()
      if !enabled {
        source = nil
        boundMovie = ""
        collector = MovieMindCoverage()
      }
    }
  }
  @Published var watchEnabled = UserDefaults.standard.bool(forKey: "movieMind.watch") {
    didSet {
      UserDefaults.standard.set(watchEnabled, forKey: "movieMind.watch")
      collector = MovieMindCoverage()
      updateFlags()
    }
  }
  @Published var ratingEnabled =
    UserDefaults.standard.object(forKey: "movieMind.rating") as? Bool ?? true
  {
    didSet {
      UserDefaults.standard.set(ratingEnabled, forKey: "movieMind.rating")
      updateFlags()
    }
  }
  @Published var recommendationEnabled =
    UserDefaults.standard.object(forKey: "movieMind.recommend") as? Bool ?? true
  { didSet { UserDefaults.standard.set(recommendationEnabled, forKey: "movieMind.recommend") } }
  @Published var status = "MovieMind 未连接"
  @Published private(set) var temporaryLoginAvailable = false
  @Published private(set) var temporarySession = false
  @Published var suggestion: Suggestion?
  @Published private(set) var boundMovie = ""
  private var seenSuggestions = Set<String>()
  private var retryTask: Task<Void, Never>?
  init() {
    retryTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        guard !Task.isCancelled else { return }
        self?.retry()
      }
    }
  }
  deinit { retryTask?.cancel() }
  private weak var source: AVPlayerItem?
  private var bindingAccount: String?
  private var bindingOrigin = ""
  private var editionId = "", sessionId = ""
  private var duration: Int64 = 0
  private var lastFlush: Int64 = 0
  private var wasEnded = false
  private var collector = MovieMindCoverage()
  private lazy var transport = MovieMindTransport(report: { [weak self] message, suggestion in
    Task { @MainActor in
      guard let self else { return }
      self.status = message
      if let suggestion, let movie = suggestion["movieId"], let session = suggestion["sessionId"],
        self.ratingEnabled, !self.seenSuggestions.contains(session)
      {
        self.seenSuggestions.insert(session)
        self.suggestion = Suggestion(movieId: movie, sessionId: session)
      }
    }
  })
  var origin: String { UserDefaults.standard.string(forKey: "movieMind.origin") ?? "" }
  private var account: String? { UserDefaults.standard.string(forKey: "movieMind.userId") }
  private func updateFlags() {
    let e = enabled
    let w = watchEnabled
    let r = ratingEnabled
    Task {
      await transport.configure(enabled: e, watch: w, rating: r)
      if e { await transport.flush() }
    }
  }
  func login(origin: String, name: String, password: String, persistent: Bool = true) async -> Bool
  {
    guard boundMovie.isEmpty else {
      status = "请先关闭 MovieMind 结束当前观影绑定，再登录账号；播放继续"
      return false
    }
    do {
      try await transport.login(
        origin: origin, name: name, password: password, persistent: persistent)
      temporaryLoginAvailable = false
      temporarySession = !persistent
      updateFlags()
      return true
    } catch {
      if let failure = error as? MovieMindLoginFailure, case .sessionStorage = failure {
        temporaryLoginAvailable = true
      } else {
        temporaryLoginAvailable = false
      }
      status = MovieMindLoginFailure.message(for: error)
      return false
    }
  }
  func get(_ path: String) async throws -> Data {
    let owner = account
    let service = origin
    let data = try await transport.request(path)
    guard owner == account, service == origin else { throw URLError(.userAuthenticationRequired) }
    return data
  }
  func bind(
    movie: String, edition: String, duration: Int64, source: AVPlayerItem?, actualDuration: Double
  ) -> Bool {
    guard let source, actualDuration.isFinite, actualDuration > 0,
      abs(actualDuration - Double(duration)) <= 1000
    else { return false }
    flush()
    self.source = source
    boundMovie = movie
    bindingAccount = account
    bindingOrigin = origin
    editionId = edition
    self.duration = duration
    sessionId = UUID().uuidString
    collector = MovieMindCoverage()
    wasEnded = false
    status = "已确认作品与剪辑版本（仅本机绑定）"
    updateFlags()
    return true
  }
  func discontinuity() { collector.discontinuity() }
  func sample(
    source: AVPlayerItem?, position: Double, duration: Double, playing: Bool, rate: Double,
    seeking: Bool, foreground: Bool, ended: Bool = false
  ) {
    guard enabled else { return }
    if !boundMovie.isEmpty && (bindingAccount != account || bindingOrigin != origin) {
      self.source = nil
      boundMovie = ""
      collector = MovieMindCoverage()
      suggestion = nil
      status = "账号或服务已改变，请重新确认作品与版本"
      return
    }
    guard let current = source, self.source === current else {
      if !boundMovie.isEmpty {
        flush()
        self.source = nil
        boundMovie = ""
        status = "片源实例已改变，请重新确认作品与剪辑版本"
      }
      return
    }
    guard watchEnabled else { return }
    guard position.isFinite, duration.isFinite, position >= 0 else {
      collector.discontinuity()
      return
    }
    let now = Int64(ProcessInfo.processInfo.systemUptime * 1000)

    if seeking || !foreground || abs(duration - Double(self.duration)) > 1000 {
      collector.discontinuity()
    }
    collector.sample(
      position: Int64(position), now: now, playing: playing && !seeking && foreground, rate: rate)
    if now - lastFlush >= 30000 || ended && !wasEnded {
      flush(ended: ended)
      lastFlush = now
    }
    wasEnded = ended
  }
  func flush(ended: Bool = false) {
    guard let batch = collector.drain(), !sessionId.isEmpty else { return }
    let event: [String: Any] = [
      "id": UUID().uuidString, "sessionId": sessionId, "editionId": editionId,
      "intervals": batch.intervals.map { ["start": $0.start, "end": $0.end] },
      "elapsedMs": batch.elapsedMs, "rate": batch.rate, "ended": ended,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
    let movie = boundMovie
    let owner = bindingAccount
    let service = bindingOrigin
    Task {
      await transport.enqueue(
        path: "watch/events", body: data, method: "POST", movieId: movie, account: owner,
        origin: service)
    }
  }
  func retry() {
    updateFlags()
    Task { await transport.flush() }
  }
  func saveRecord(
    movie: String, rating: Double?, comment: String, together: Bool, original: [String: Any]
  ) async -> Bool {
    let owner = account
    let service = origin
    var record: [String: Any] = ["movieId": movie, "source": "manual"]
    if !original.isEmpty { record = original }
    let revision = record["revision"] as? Int ?? 0
    record["status"] = "seen"
    record["rating"] = rating.map { $0 as Any } ?? NSNull()
    record["comment"] = comment
    record["together"] = together
    record["deleted"] = false
    guard
      let body = try? JSONSerialization.data(withJSONObject: [
        "record": record, "expectedRevision": revision, "mutationId": UUID().uuidString,
      ])
    else { return false }
    return await transport.enqueue(
      path: "records/" + movie, body: body, method: "PUT", account: owner, origin: service)
  }
  func completion(session: String, decision: String) {
    guard !session.isEmpty,
      let body = try? JSONSerialization.data(withJSONObject: ["decision": decision])
    else { return }
    let owner = account
    let service = origin
    Task {
      await transport.enqueue(
        path: "watch/sessions/" + session + "/completion", body: body, method: "PUT",
        account: owner, origin: service)
    }
    suggestion = nil
  }
  func drafts() async throws -> Data { try await transport.drafts() }
  func resolve(id: String, body: Data?) async throws {
    try await transport.resolve(id: id, body: body)
  }
}
