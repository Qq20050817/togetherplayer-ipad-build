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
private actor MovieMindTransport {
  private let directory = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "MovieMind", isDirectory: true)
  private var pending = [MovieMindPending]()
  private var loaded = false
  private var blocked = false
  private var flushing = false
  private var enabled = false
  private var watchEnabled = false
  private var ratingEnabled = true
  private let report: @Sendable (String, [String: String]?) -> Void
  private let session: URLSession
  init(report: @escaping @Sendable (String, [String: String]?) -> Void) {
    self.report = report
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 3
    config.timeoutIntervalForResource = 4
    session = URLSession(configuration: config, delegate: MovieMindNoRedirect(), delegateQueue: nil)
  }
  private func load() throws {
    if loaded { return }
    loaded = true
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("outbox.json")
      if FileManager.default.fileExists(atPath: file.path) {
        let data = try Data(contentsOf: file)
        guard data.count < 8 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        pending = try JSONDecoder().decode([MovieMindPending].self, from: data)
      }
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
  private func storedToken() -> String {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MovieMind",
      kSecAttrAccount as String: "session", kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }
  private func storeToken(_ value: String) throws {
    let key: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MovieMind",
      kSecAttrAccount as String: "session",
    ]
    SecItemDelete(key as CFDictionary)
    var q = key
    q[kSecValueData as String] = Data(value.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else {
      throw URLError(.userAuthenticationRequired)
    }
  }
  func configure(enabled: Bool, watch: Bool, rating: Bool) {
    self.enabled = enabled
    watchEnabled = watch
    ratingEnabled = rating
  }
  func request(
    _ path: String, body: Data? = nil, method: String = "GET", origin: String? = nil,
    token: String? = nil
  ) async throws -> Data {
    let root = origin ?? UserDefaults.standard.string(forKey: "movieMind.origin") ?? ""
    guard let base = URLComponents(string: root), base.user == nil, base.password == nil,
      base.query == nil, base.fragment == nil, base.path.isEmpty || base.path == "/",
      base.scheme == "https"
        || base.scheme == "http" && ["127.0.0.1", "localhost"].contains(base.host ?? ""),
      let url = URL(string: root + "/api/" + path)
    else { throw URLError(.badURL) }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("1", forHTTPHeaderField: "X-MovieMind")
    req.setValue("native", forHTTPHeaderField: "X-MovieMind-Client")
    let auth = token ?? storedToken()
    if !auth.isEmpty { req.setValue("Bearer " + auth, forHTTPHeaderField: "Authorization") }
    let (data, response) = try await session.data(for: req)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard response.statusCode >= 200, response.statusCode < 300 else {
      throw NSError(domain: "MovieMindHTTP", code: response.statusCode)
    }
    guard data.count < 2 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
    return data
  }
  func login(origin: String, name: String, password: String) async throws {
    try load()
    let before = UserDefaults.standard.string(forKey: "movieMind.origin") ?? ""
    let target = origin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard pending.isEmpty || before == target else { throw URLError(.userAuthenticationRequired) }
    let data = try await request(
      "auth/login",
      body: JSONSerialization.data(withJSONObject: ["name": name, "password": password]),
      method: "POST", origin: target, token: "")
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: String],
      let token = result["token"], let user = result["userId"]
    else { throw URLError(.badServerResponse) }
    let owner = UserDefaults.standard.string(forKey: "movieMind.userId")
    guard pending.isEmpty || owner == user else { throw URLError(.userAuthenticationRequired) }
    try storeToken(token)
    UserDefaults.standard.set(target, forKey: "movieMind.origin")
    UserDefaults.standard.set(user, forKey: "movieMind.userId")
    report("已登录独立 MovieMind 账号", nil)
  }
  func enqueue(path: String, body: Data, method: String, movieId: String = "") async -> Bool {
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
          pending.removeAll { $0.id == item.id }
          try persist()
          if item.path == "watch/events",
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
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
  private var editionId = "", sessionId = ""
  private var duration: Int64 = 0
  private var lastFlush: Int64 = 0
  private var lastRate = 1.0
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
  private func updateFlags() {
    let e = enabled
    let w = watchEnabled
    let r = ratingEnabled
    Task {
      await transport.configure(enabled: e, watch: w, rating: r)
      if e { await transport.flush() }
    }
  }
  func login(origin: String, name: String, password: String) async -> Bool {
    do {
      try await transport.login(origin: origin, name: name, password: password)
      updateFlags()
      return true
    } catch {
      status = "登录失败，请核对地址和账号；待同步内容只能交给原账号和服务"
      return false
    }
  }
  func get(_ path: String) async throws -> Data { try await transport.request(path) }
  func bind(
    movie: String, edition: String, duration: Int64, source: AVPlayerItem?, actualDuration: Double
  ) -> Bool {
    guard let source, actualDuration.isFinite, actualDuration > 0,
      abs(actualDuration - Double(duration)) <= 1000
    else { return false }
    flush()
    self.source = source
    boundMovie = movie
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
    if rate != lastRate {
      flush()
      collector.discontinuity()
      lastRate = rate
    }
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
    Task {
      await transport.enqueue(path: "watch/events", body: data, method: "POST", movieId: movie)
    }
  }
  func retry() {
    updateFlags()
    Task { await transport.flush() }
  }
  func saveRecord(
    movie: String, rating: Double?, comment: String, together: Bool, original: [String: Any]
  ) async -> Bool {
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
    return await transport.enqueue(path: "records/" + movie, body: body, method: "PUT")
  }
  func completion(session: String, decision: String) {
    guard !session.isEmpty,
      let body = try? JSONSerialization.data(withJSONObject: ["decision": decision])
    else { return }
    Task {
      await transport.enqueue(
        path: "watch/sessions/" + session + "/completion", body: body, method: "PUT")
    }
    suggestion = nil
  }
  func drafts() async throws -> Data { try await transport.drafts() }
  func resolve(id: String, body: Data?) async throws {
    try await transport.resolve(id: id, body: body)
  }
}
