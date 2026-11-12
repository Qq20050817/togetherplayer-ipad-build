import SwiftUI

@MainActor final class MovieMindJournalStore: ObservableObject {
  let client: MovieMindClient
  let scope: MovieMindScope
  @Published var movies = [MovieMindWork]()
  @Published var records = [[String: Any]]()
  @Published var recommendation: MovieMindRecommendations?
  @Published var preferences = [String: Any]()
  @Published var votes = [String: [String: String]]()
  @Published var wishlist = [MovieMindWork]()
  @Published var paired = false
  @Published var busy = false
  @Published var message = ""
  var activeQuery = MovieMindRecommendQuery()
  init(client: MovieMindClient) {
    self.client = client
    scope = client.workspaceScope
  }
  func object(_ path: String, value: [String: Any]? = nil, method: String = "GET") async throws
    -> [String: Any]
  {
    let body = try value.map { try JSONSerialization.data(withJSONObject: $0) }
    let data = try await client.api(path, body: body, method: method, scope: scope)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw MovieMindJournalFailure.invalidReply
    }
    return object
  }
  func load() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      async let works = client.api("movies", scope: scope)
      async let rows = client.api("records", scope: scope)
      let loadedWorks = try JSONDecoder().decode([MovieMindWork].self, from: await works)
      guard let loadedRows = try await JSONSerialization.jsonObject(with: rows) as? [[String: Any]]
      else {
        throw MovieMindJournalFailure.invalidReply
      }
      let me = try await object("me")
      movies = loadedWorks
      records = loadedRows
      preferences = me["preferences"] as? [String: Any] ?? [:]
      let pair = try await object("pair")
      paired = pair["paired"] as? Bool ?? false
      if paired {
        wishlist = try await JSONDecoder().decode(
          [MovieMindWork].self, from: client.api("pair/wishlist", scope: scope))
        let data = try await client.api("pair/votes", scope: scope)
        votes = try JSONDecoder().decode([String: [String: String]].self, from: data)
      } else {
        wishlist = []
        votes = [:]
        recommendation = nil
      }
      message = ""
    } catch { message = MovieMindJournalFailure.message(error) }
  }
  func record(_ id: String) -> [String: Any] {
    records.first { $0["movieId"] as? String == id } ?? [:]
  }
  func recommend(_ query: MovieMindRecommendQuery, more: Bool = false) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      var q = more ? activeQuery : query
      q.offset = more ? activeQuery.offset + 5 : 0
      let data = try await client.api(
        "recommend", body: JSONEncoder().encode(q), method: "POST", scope: scope)
      let next = try JSONDecoder().decode(MovieMindRecommendations.self, from: data)
      if more, let old = recommendation {
        let ids = Set(old.candidates.map(\.id))
        recommendation = MovieMindRecommendations(
          candidates: old.candidates + next.candidates.filter { !ids.contains($0.id) },
          pending: next.pending, mode: next.mode, hasMore: next.hasMore)
      } else {
        recommendation = next
      }
      activeQuery = q
      message = ""
    } catch { message = MovieMindJournalFailure.message(error) }
  }
}

enum MovieMindJournalPage { case library, recommendations, pair }
private struct MovieMindEditSelection: Identifiable {
  let id = UUID()
  let work: MovieMindWork?
  var status = "seen"
}

@MainActor struct MovieMindJournalView: View {
  @ObservedObject var client: MovieMindClient
  @StateObject private var store: MovieMindJournalStore
  let page: MovieMindJournalPage
  @State private var search = "", filter = "mine"
  @State private var editor: MovieMindEditSelection?
  @State private var minutes = "", mood = "", tonightAvoid = ""
  @State private var pairRecommendation = false, rewatch = false, acceptUnknown = false
  @State private var invite = "", invitation = ""
  @State private var confirmUnpair = false, confirmPair = false, showPreferences = false
  init(client: MovieMindClient, page: MovieMindJournalPage) {
    self.client = client
    self.page = page
    _store = StateObject(wrappedValue: MovieMindJournalStore(client: client))
  }
  private var title: String {
    switch page {
    case .library: return "我的电影与评分"
    case .recommendations: return "推荐下一部"
    case .pair: return "两个人一起选"
    }
  }
  var body: some View {
    List {
      if !store.scope.configured {
        Section { Text("请先返回 MovieMind 账号页，用自己的账号登录。") }
      } else {
        if !store.message.isEmpty { Section { Text(store.message).foregroundStyle(.orange) } }
        if store.busy { ProgressView("正在读取…") }
        switch page {
        case .library: library
        case .recommendations: recommendations
        case .pair: pairing
        }
        Section {
          Text(client.status).font(.caption).textSelection(.enabled)
          Button("重试待同步评分") { client.retry() }
        } header: {
          Text("同步状态")
        }
      }
    }
    .navigationTitle(title)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("刷新") { Task { await store.load() } }.disabled(store.busy)
      }
    }
    .task { await store.load() }
    .refreshable { await store.load() }
    .onChange(of: client.workspaceGeneration) { _ in
      store.recommendation = nil
      store.wishlist = []
      store.votes = [:]
    }
    .sheet(item: $editor) { item in
      MovieMindEntryEditor(store: store, work: item.work, initialStatus: item.status)
    }
    .sheet(isPresented: $showPreferences) { MovieMindPreferencesView(store: store) }
    .alert("确认接受配对？", isPresented: $confirmPair) {
      Button("双方确认，接受邀请") {
        action {
          _ = try await store.object(
            "pair/accept", value: ["token": invite, "confirm": true], method: "POST")
          invite = ""
          client.invalidateWorkspace()
          await store.load()
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("只共享共同想看和选片投票，双方完整历史、具体评分及私人短评仍独立保存。")
    }
    .alert("解除配对？", isPresented: $confirmUnpair) {
      Button("解除配对", role: .destructive) {
        action {
          _ = try await store.object("pair", method: "DELETE")
          store.paired = false
          store.recommendation = nil
          store.wishlist = []
          store.votes = [:]
          client.invalidateWorkspace()
          await store.load()
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("共同选片权限立即结束，个人电影、评分和短评保留。")
    }
  }
  private func action(_ work: @escaping @MainActor () async throws -> Void) {
    Task {
      do { try await work() } catch { store.message = MovieMindJournalFailure.message(error) }
    }
  }
  private var library: some View {
    Group {
      Section {
        Text("记录你看过的电影、评分和短评，之后用真实反馈推荐下一部。双方各用自己的账号记录。")
        Button("添加已看电影") { editor = MovieMindEditSelection(work: nil) }
          .accessibilityIdentifier("moviemind-add-seen")
        Button("添加想看候选") { editor = MovieMindEditSelection(work: nil, status: "want") }
        Button("我的口味与雷区") { showPreferences = true }
        TextField("搜索片名、译名或标准 ID", text: $search)
        Picker("显示范围", selection: $filter) {
          Text("我的记录").tag("mine")
          Text("全部电影资料").tag("all")
        }
      }
      Section {
        let works = store.movies.filter {
          $0.matches(search)
            && (filter == "all"
              || (!store.record($0.id).isEmpty && store.record($0.id)["deleted"] as? Bool != true))
        }
        if works.isEmpty {
          Text("还没有匹配的记录。可以添加已看电影，或切换到全部电影资料选择已有作品。")
            .foregroundStyle(.secondary)
        }
        ForEach(works) { work in
          Button {
            editor = MovieMindEditSelection(work: work)
          } label: {
            VStack(alignment: .leading, spacing: 5) {
              Text("\(work.title) · \(String(work.year))").font(.headline)
              let r = store.record(work.id)
              if !r.isEmpty, r["deleted"] as? Bool != true {
                Text(
                  MovieMindJournal.statusName(r["status"] as? String ?? "want") + " · "
                    + ((r["rating"] as? Double).map { String(format: "%.1f 分", $0) } ?? "未评分")
                )
                .font(.subheadline).foregroundStyle(.secondary)
                if let comment = r["comment"] as? String, !comment.isEmpty {
                  Text(comment).font(.caption).lineLimit(3)
                }
              } else {
                Text("添加到我的档案").font(.caption).foregroundStyle(.secondary)
              }
            }
          }.tint(.primary)
        }
      } header: {
        Text("电影档案")
      }
    }
  }
  private var recommendations: some View {
    Group {
      Section {
        Text("根据你明确给出的评分、喜欢和不喜欢排序；已看默认排除。评分较少时会保守推荐，双人资料不足时先投票。")
        Text("候选来自服务中已添加的电影资料；可以先添加想看电影作为候选。").font(.caption)
        TextField("最长片长（分钟，可选）", text: $minutes).keyboardType(.numberPad)
        TextField("这次想看的元素，用逗号分隔", text: $mood)
        TextField("这次避开的内容，用逗号分隔", text: $tonightAvoid)
        Toggle("这次愿意重看", isOn: $rewatch)
        if store.paired { Toggle("同时满足我们两个人", isOn: $pairRecommendation) }
        Toggle("仅本次接受雷区信息未知", isOn: $acceptUnknown)
        Button("按真实反馈推荐") {
          let duration = minutes.isEmpty ? 0 : Int(minutes)
          guard let duration, (0...1000).contains(duration) else {
            store.message = "请填写0至1000之间的分钟数"
            return
          }
          var q = MovieMindRecommendQuery()
          q.pair = pairRecommendation && store.paired
          q.rewatch = rewatch
          q.acceptUnknown = acceptUnknown
          q.maxMinutes = duration
          q.mood = MovieMindJournal.tags(mood)
          q.tonightAvoid = MovieMindJournal.tags(tonightAvoid)
          Task { await store.recommend(q) }
        }.disabled(store.busy).accessibilityIdentifier("moviemind-native-recommend")
      }
      if let result = store.recommendation {
        if result.mode == "vote" { Text("双方评价资料还不够，先选择愿意看、都可以或跳过。") }
        Section {
          if result.candidates.isEmpty {
            Text("暂无符合条件的候选。可以先添加想看电影，或调整这次的条件；已有观看记录不会被当成新的推荐。")
          }
          ForEach(result.candidates) { candidate in candidateView(candidate, pending: false) }
          if result.hasMore {
            Button("查看更多候选") { Task { await store.recommend(store.activeQuery, more: true) } }
              .disabled(store.busy)
          }
        } header: {
          Text("主要候选")
        }
        if !result.pending.isEmpty {
          Section {
            DisclosureGroup("待核实内容 · \(result.pending.count) 部") {
              ForEach(result.pending) { candidate in candidateView(candidate, pending: true) }
            }
          } footer: {
            Text("关键内容资料缺失会保留为未知。只有你明确接受信息不足后才参与普通候选。")
          }
        }
      }
    }
  }
  private func candidateView(_ candidate: MovieMindCandidate, pending: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(candidate.movie.title) · \(String(candidate.movie.year))").font(.headline)
      Text(candidate.label).font(.subheadline).foregroundStyle(.secondary)
      ForEach(candidate.reasons, id: \.self) { Text("• " + $0).font(.caption) }
      ForEach(candidate.gaps, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
      Button("加入想看") { editor = MovieMindEditSelection(work: candidate.movie, status: "want") }
      if store.activeQuery.pair && !pending {
        HStack {
          ForEach([("yes", "愿意看"), ("maybe", "都可以"), ("skip", "跳过")], id: \.0) { vote in
            Button(vote.1) {
              action {
                _ = try await store.object(
                  "pair/vote",
                  value: [
                    "movieId": candidate.id, "value": vote.0,
                    "acceptUnknown": store.activeQuery.acceptUnknown,
                    "rewatch": store.activeQuery.rewatch,
                  ], method: "POST")
                await store.load()
              }
            }.buttonStyle(.bordered)
          }
        }
        voteText(candidate.id)
      }
    }.padding(.vertical, 5)
  }
  private func voteText(_ id: String) -> some View {
    let values = store.votes[id] ?? [:]
    return Text("我的选择：\(voteName(values["mine"])) · 对方：\(voteName(values["partner"]))").font(
      .caption)
  }
  private func voteName(_ value: String?) -> String {
    ["yes": "愿意看", "maybe": "都可以", "skip": "跳过"][value ?? ""] ?? "尚未投票"
  }
  private var pairing: some View {
    Group {
      Section {
        Text("两个人各自评分、写私人短评。配对后，只共享主动公开的共同想看和候选投票。")
        if store.paired {
          Text("已配对")
          Button("解除配对", role: .destructive) { confirmUnpair = true }
        } else {
          Button("我同意配对，生成10分钟邀请") {
            action {
              let result = try await store.object("invites", value: [:], method: "POST")
              guard let token = result["token"] as? String else {
                throw MovieMindJournalFailure.invalidReply
              }
              invitation = token
            }
          }
          if !invitation.isEmpty {
            Text(invitation).font(.caption).textSelection(.enabled)
            Button("撤销我的邀请") {
              action {
                _ = try await store.object("invites", method: "DELETE")
                invitation = ""
              }
            }
          }
          TextField("粘贴对方的邀请凭证", text: $invite).textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("核对并接受邀请") { confirmPair = true }.disabled(invite.isEmpty)
        }
      }
      if store.paired {
        Section {
          if store.wishlist.isEmpty { Text("双方都将同一部电影设为想看并主动共享后，会显示在这里。") }
          ForEach(store.wishlist) { work in
            VStack(alignment: .leading) {
              Text(work.title)
              voteText(work.id)
            }
          }
          Text("双方同意后，由房主在原有选片入口确认本机片源和播放，不会自动换片。")
        } header: {
          Text("共同想看")
        }
      }
    }
  }
}

@MainActor private struct MovieMindEntryEditor: View {
  @ObservedObject var store: MovieMindJournalStore
  let work: MovieMindWork?
  let initialStatus: String
  @Environment(\.dismiss) private var dismiss
  @State private var title = "", originalTitle = "", year = "", runtime = "", standardID = ""
  @State private var present = "", absent = "", status = "seen", rating = "", comment = "",
    date = ""
  @State private var likes = "", dislikes = "", experience = ""
  @State private var together = false, favorite = false, sharedWish = false, saving = false
  @State private var confirmDelete = false
  @State private var message = ""
  @State private var created: MovieMindWork?
  @State private var manualID = "manual:" + UUID().uuidString
  @State private var original = [String: Any]()
  var body: some View {
    NavigationStack {
      Form {
        if work == nil && created == nil {
          Section("电影资料") {
            TextField("中文片名（必填）", text: $title).accessibilityIdentifier("moviemind-entry-title")
            TextField("年份（必填）", text: $year).keyboardType(.numberPad)
            TextField("原名（可选）", text: $originalTitle)
            TextField("片长分钟（未知可留空）", text: $runtime).keyboardType(.numberPad)
            TextField("已有 TMDB/IMDb 标准ID（可选）", text: $standardID).textInputAutocapitalization(
              .never
            ).autocorrectionDisabled()
            Text("同一作品优先从已有资料选择。手工资料使用独立 ID，同名不同年份不会自动合并。").font(.caption)
            ForEach(
              store.movies.filter { !$0.title.isEmpty && !title.isEmpty && $0.matches(title) }
                .prefix(5)
            ) { existing in
              Button("使用已有：\(existing.title)（\(String(existing.year))）") {
                created = existing
                loadRecord(existing.id)
              }
            }
          }
          Section {
            DisclosureGroup("可选：我核实过的电影元素") {
              TextField("确认出现的类型或元素，逗号分隔", text: $present)
              TextField("有证据确认未出现的内容，逗号分隔", text: $absent)
              Text("不要仅凭简介填写‘没有血腥/突脸’。未填写的内容保持未知。").font(.caption)
            }
          }
        } else {
          Text((work ?? created)?.title ?? "").font(.headline)
        }
        Section("我的观影记录") {
          Picker("观看状态", selection: $status) {
            ForEach(MovieMindJournal.statuses, id: \.0) { Text($0.1).tag($0.0) }
          }
          Picker("个人评分", selection: $rating) {
            Text("未评分").tag("")
            ForEach(0...20, id: \.self) { n in
              Text(String(format: "%.1f", Double(n) / 2)).tag(String(Double(n) / 2))
            }
          }
          TextField("私人评价（可选）", text: $comment, axis: .vertical).lineLimit(3...8)
            .accessibilityIdentifier("moviemind-entry-comment")
          TextField("观影日期（可选，YYYY-MM-DD）", text: $date).textInputAutocapitalization(.never)
          Toggle("这次是共同观看", isOn: $together)
          Toggle("收藏这部电影", isOn: $favorite)
          Toggle("主动共享这部想看电影", isOn: $sharedWish)
        }
        Section("可选：我喜欢和不喜欢什么") {
          TextField("喜欢的元素，逗号分隔", text: $likes)
          TextField("不喜欢的元素，逗号分隔", text: $dislikes)
          TextField("体验描述，逗号分隔", text: $experience)
          Text("体验描述和技术故障不会自动变成评分。评分和私人短评属于你自己的账号。").font(.caption)
        }
        if !message.isEmpty { Text(message).foregroundStyle(.orange) }
        Text(store.client.status).font(.caption)
        Button("保存我的记录") { save(deleted: false) }.disabled(saving)
          .accessibilityIdentifier("moviemind-save-entry")
        if !original.isEmpty {
          Button("撤回这条观影记录", role: .destructive) { confirmDelete = true }.disabled(saving)
        }
      }.navigationTitle("记录与评价").toolbar { Button("取消") { dismiss() } }
        .interactiveDismissDisabled(saving)
        .task {
          status = initialStatus
          if let work { loadRecord(work.id) }
        }
        .alert("撤回这条记录？", isPresented: $confirmDelete) {
          Button("确认撤回", role: .destructive) { save(deleted: true) }
          Button("取消", role: .cancel) {}
        } message: {
          Text("保留电影资料和修订历史，不再用这条记录学习你的口味。")
        }
    }
  }
  private func loadRecord(_ id: String) {
    original = store.record(id)
    guard !original.isEmpty else {
      status = initialStatus
      return
    }
    status = original["status"] as? String ?? initialStatus
    rating = (original["rating"] as? Double).map { String($0) } ?? ""
    comment = original["comment"] as? String ?? ""
    date = original["watchedOn"] as? String ?? ""
    together = original["together"] as? Bool ?? false
    favorite = original["favorite"] as? Bool ?? false
    sharedWish = original["sharedWish"] as? Bool ?? false
    likes = (original["likes"] as? [String] ?? []).joined(separator: "，")
    dislikes = (original["dislikes"] as? [String] ?? []).joined(separator: "，")
    experience = (original["experience"] as? [String] ?? []).joined(separator: "，")
  }
  private func save(deleted: Bool) {
    saving = true
    Task {
      defer { saving = false }
      do {
        let id = (work ?? created)?.id ?? (standardID.isEmpty ? manualID : standardID)
        let body = try MovieMindJournal.recordBody(
          movie: id, original: original, status: status, rating: Double(rating),
          comment: comment, date: date, together: together, likes: likes, dislikes: dislikes,
          experience: experience,
          favorite: favorite, sharedWish: sharedWish, deleted: deleted)
        if work == nil && created == nil {
          let metadata = try MovieMindJournal.workBody(
            id: id, title: title, originalTitle: originalTitle,
            year: Int(year) ?? 0, runtime: runtime.isEmpty ? 0 : (Int(runtime) ?? -1),
            present: present, absent: absent)
          let response = try await store.client.api(
            "movies/" + id, body: metadata, method: "PUT", scope: store.scope)
          let saved = try JSONDecoder().decode(MovieMindWork.self, from: response)
          guard saved.id == id else { throw MovieMindJournalFailure.invalidReply }
          created = saved
        }
        guard await store.client.saveJournal(movie: id, body: body, scope: store.scope) else {
          message = store.client.status
          return
        }
        await store.load()
        dismiss()
      } catch { message = MovieMindJournalFailure.message(error) }
    }
  }
}

@MainActor private struct MovieMindPreferencesView: View {
  @ObservedObject var store: MovieMindJournalStore
  @Environment(\.dismiss) private var dismiss
  @State private var likes = "", avoid = "", anchor = "", message = ""
  @State private var saving = false
  var body: some View {
    NavigationStack {
      Form {
        Text("只修改你自己的口味，不会套用到另一位观众。关键内容未知的候选会放到待核实中。")
        TextField("喜欢的元素，逗号分隔", text: $likes)
        TextField("硬性避开的内容，逗号分隔", text: $avoid)
        TextField("我的评分锚点（可选，0到10）", text: $anchor).keyboardType(.decimalPad)
        Text(message).foregroundStyle(.orange)
        Button("保存我的口味") {
          saving = true
          Task {
            defer { saving = false }
            do {
              let value: Any =
                anchor.isEmpty ? NSNull() : (Double(anchor).map { $0 as Any } ?? "invalid")
              if !anchor.isEmpty {
                guard let n = Double(anchor), n.isFinite, (0...10).contains(n) else {
                  throw MovieMindJournalFailure.invalidInput
                }
              }
              _ = try await store.object(
                "preferences",
                value: [
                  "likes": MovieMindJournal.tags(likes), "hardAvoid": MovieMindJournal.tags(avoid),
                  "ratingAnchor": value, "revision": store.preferences["revision"] as? Int ?? 0,
                ], method: "PUT")
              await store.load()
              dismiss()
            } catch { message = MovieMindJournalFailure.message(error) }
          }
        }.disabled(saving)
      }.navigationTitle("我的口味与雷区").toolbar { Button("取消") { dismiss() } }
        .task {
          likes = (store.preferences["likes"] as? [String] ?? []).joined(separator: "，")
          avoid = (store.preferences["hardAvoid"] as? [String] ?? []).joined(separator: "，")
          anchor = (store.preferences["ratingAnchor"] as? Double).map { String($0) } ?? ""
        }
    }
  }
}

@MainActor struct MovieMindEditionEditor: View {
  @ObservedObject var client: MovieMindClient
  let scope: MovieMindScope
  let movie: String
  let title: String
  let saved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var label = "", seconds = "", message = ""
  @State private var saving = false
  @State private var identity = UUID().uuidString
  var body: some View {
    NavigationStack {
      Form {
        Text(title).font(.headline)
        Text("按实际剪辑版本分别登记准确片长。不同清晰度可用同一版本；剪辑不同请新建版本。")
        TextField("版本名称，例如院线版", text: $label)
        TextField("准确片长（秒，可带小数）", text: $seconds).keyboardType(.decimalPad)
        Text(message).foregroundStyle(.orange)
        Button("确认并保存版本") {
          saving = true
          Task {
            defer { saving = false }
            do {
              guard let duration = Double(seconds), duration.isFinite, duration > 0,
                duration <= 86400,
                !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              else {
                throw MovieMindJournalFailure.invalidInput
              }
              let body = try JSONSerialization.data(withJSONObject: [
                "id": identity, "movieId": movie,
                "label": label, "durationMs": Int64((duration * 1000).rounded()),
              ])
              let data = try await client.api("editions", body: body, method: "POST", scope: scope)
              guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                reply["id"] as? String == identity, reply["movieId"] as? String == movie
              else {
                throw MovieMindJournalFailure.invalidReply
              }
              saved()
              dismiss()
            } catch { message = MovieMindJournalFailure.message(error) }
          }
        }.disabled(saving)
      }.navigationTitle("确认剪辑版本").toolbar { Button("取消") { dismiss() } }
    }
  }
}
