import Foundation

struct MovieMindScope: Equatable, Hashable {
  let origin: String
  let account: String
  var configured: Bool { !origin.isEmpty && !account.isEmpty }
}

struct MovieMindWork: Decodable, Identifiable {
  let id: String
  let title: String
  let year: Int
  let originalTitle: String?
  let runtime: Int?
  let aliases: [String]?
  func matches(_ query: String) -> Bool {
    query.isEmpty
      || ([title, originalTitle ?? "", id] + (aliases ?? []))
        .contains { $0.localizedCaseInsensitiveContains(query) }
  }
}

struct MovieMindCandidate: Decodable, Identifiable {
  let movie: MovieMindWork
  let label: String
  let reasons: [String]
  let gaps: [String]
  var id: String { movie.id }
}
struct MovieMindRecommendations: Decodable {
  let candidates: [MovieMindCandidate]
  let pending: [MovieMindCandidate]
  let mode: String
  let hasMore: Bool
}
struct MovieMindRecommendQuery: Encodable {
  var pair = false, rewatch = false, acceptUnknown = false
  var maxMinutes = 0, offset = 0
  var tonightAvoid = [String](), mood = [String]()
}

enum MovieMindJournalFailure: Error {
  case changedAccount, invalidInput, invalidReply
  var message: String {
    switch self {
    case .changedAccount: return "账号或服务已改变，请重新打开电影档案；原草稿保留"
    case .invalidInput: return "请核对片名、年份、日期、半分评分及标签，评价最多约2000字节"
    case .invalidReply: return "服务回执不完整，原内容保留，请刷新核对"
    }
  }
  static func message(_ error: Error) -> String {
    if let e = error as? Self { return e.message }
    let e = error as NSError
    if e.domain == "MovieMindHTTP" {
      if e.code == 401 { return "登录已过期，请返回账号页重新登录；本机草稿保留" }
      if e.code == 409 { return "资料已在其他设备更改，请刷新核对；未覆盖对方修改" }
      if e.code == 403 { return "此操作尚未获授权，请核对登录及双方配对状态" }
      if e.code == 429 { return "操作较频繁，请稍后重试" }
    }
    return "暂时无法连接 MovieMind，原输入保留，请稍后重试"
  }
}

enum MovieMindJournal {
  static let statuses = [
    ("want", "想看"), ("watching", "观看中"), ("seen", "已看"),
    ("hold", "暂时搁置"), ("dropped", "弃看"), ("rewatch", "重看"),
  ]
  static func statusName(_ status: String) -> String {
    statuses.first { $0.0 == status }?.1 ?? status
  }
  static func tags(_ text: String) -> [String] {
    var seen = Set<String>()
    return text.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }
  static func validTags(_ values: [String]) -> Bool {
    values.count <= 40 && values.allSatisfy { !$0.isEmpty && $0.utf8.count <= 100 }
  }
  static func validID(_ id: String) -> Bool {
    id.range(
      of: "^(tmdb:[1-9][0-9]{0,11}|imdb:tt[0-9]{5,12}|manual:[A-Za-z0-9_-]{8,80})$",
      options: .regularExpression) != nil
  }
  static func recordBody(
    movie: String, original: [String: Any], status: String,
    rating: Double?, comment: String, date: String, together: Bool,
    likes: String, dislikes: String, experience: String,
    favorite: Bool, sharedWish: Bool, deleted: Bool = false
  ) throws -> Data {
    let positive = tags(likes)
    let negative = tags(dislikes)
    let features = tags(experience)
    guard validID(movie), statuses.contains(where: { $0.0 == status }), comment.utf8.count <= 2000,
      validTags(positive), validTags(negative), validTags(features),
      rating.map({ $0.isFinite && (0...10).contains($0) && ($0 * 2).rounded() == $0 * 2 }) ?? true
    else { throw MovieMindJournalFailure.invalidInput }
    if !date.isEmpty {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.timeZone = TimeZone(secondsFromGMT: 0)
      f.dateFormat = "yyyy-MM-dd"
      f.isLenient = false
      guard let d = f.date(from: date), f.string(from: d) == date else {
        throw MovieMindJournalFailure.invalidInput
      }
    }
    let keys = Set([
      "movieId", "status", "favorite", "watchedOn", "together", "sharedWish", "rating", "likes",
      "dislikes", "experience", "comment", "source", "revision", "createdAt", "updatedAt",
      "deleted",
    ])
    var record = original.filter { keys.contains($0.key) }
    let revision = original["revision"] as? Int ?? 0
    guard revision >= 0,
      original["movieId"] as? String == nil || original["movieId"] as? String == movie
    else {
      throw MovieMindJournalFailure.invalidInput
    }
    record["movieId"] = movie
    record["source"] = original["source"] as? String ?? "manual"
    record["status"] = status
    record["rating"] = rating.map { $0 as Any } ?? NSNull()
    record["comment"] = comment
    record["watchedOn"] = date
    record["together"] = together
    record["likes"] = positive
    record["dislikes"] = negative
    record["experience"] = features
    record["favorite"] = favorite
    record["sharedWish"] = sharedWish
    record["deleted"] = deleted
    return try JSONSerialization.data(withJSONObject: [
      "record": record, "expectedRevision": revision,
      "mutationId": UUID().uuidString,
    ])
  }
  static func workBody(
    id: String, title: String, originalTitle: String, year: Int, runtime: Int,
    present: String, absent: String
  ) throws -> Data {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let positive = tags(present)
    let negative = tags(absent)
    guard validID(id), !title.isEmpty, title.utf8.count <= 300, originalTitle.utf8.count <= 300,
      (1880...2200).contains(year), (0...1000).contains(runtime), validTags(positive),
      validTags(negative),
      Set(positive).isDisjoint(with: Set(negative))
    else { throw MovieMindJournalFailure.invalidInput }
    var evidence = [String: Any]()
    let now = ISO8601DateFormatter().string(from: Date())
    for (values, state) in [(positive, "present"), (negative, "absent")] {
      for tag in values {
        evidence[tag] =
          [
            "state": state, "source": "本人确认", "method": "human",
            "reliability": 0.9, "updatedAt": now,
          ] as [String: Any]
      }
    }
    return try JSONSerialization.data(withJSONObject: [
      "id": id, "title": title, "originalTitle": originalTitle,
      "year": year, "runtime": runtime, "poster": "", "aliases": [], "tags": evidence,
      "source": "manual", "revision": 0,
    ])
  }
}
