import AVFoundation
import SwiftUI

private struct MovieMindMovie: Decodable, Identifiable {
  let id: String
  let title: String
  let year: Int
}
private struct MovieMindEdition: Decodable, Identifiable {
  let id: String
  let movieId: String
  let label: String
  let durationMs: Int64
}

@MainActor struct MovieMindView: View {
  @ObservedObject var client: MovieMindClient
  let model: TestClient
  @Environment(\.dismiss) private var dismiss
  @State private var origin = ""
  @State private var name = ""
  @State private var password = ""
  @State private var loggingIn = false
  @State private var movies = [MovieMindMovie]()
  @State private var editions = [MovieMindEdition]()
  @State private var selectedMovie = ""
  @State private var query = ""
  @State private var context: AVPlayerItem?
  @State private var drafts = [MovieMindPending]()
  @State private var selectedEdition: MovieMindEdition?
  @State private var rating: MovieMindClient.Suggestion?
  @State private var conflict: MovieMindPending?
  var body: some View {
    NavigationStack {
      Form {
        Section("独立接入开关") {
          Toggle("启用 MovieMind", isOn: $client.enabled)
          Toggle("为我们推荐入口", isOn: $client.recommendationEnabled)
          Toggle("实际播放区间记录", isOn: $client.watchEnabled)
          Toggle("可跳过的片尾评分卡", isOn: $client.ratingEnabled)
          Text("MovieMind 不接管播放器；关闭或服务失败时，原有同步、选片和播放继续运行。").font(.caption)
        }
        Section("个人账号") {
          TextField("独立服务 HTTPS 地址", text: $origin).textInputAutocapitalization(.never)
            .autocorrectionDisabled().keyboardType(.URL).disabled(loggingIn)
          TextField("用户名", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
            .disabled(loggingIn)
          SecureField("密码", text: $password).disabled(loggingIn)
          Button("登录此服务") { signIn(persistent: true) }.disabled(loginDisabled)
          if client.temporaryLoginAvailable {
            Button("仅本次登录") { signIn(persistent: false) }.disabled(loginDisabled)
            Text("会话仅保留在当前 App 进程中，重启后需重新登录；待同步草稿仍保留。").font(.caption)
          }
          if client.temporarySession {
            Text("当前为仅本次登录，App 重启后需要重新登录。").font(.caption)
          }
          if loggingIn { ProgressView("正在登录…") }
          Text(client.status).font(.caption).textSelection(.enabled)
            .accessibilityIdentifier("moviemind-sync-status")
        }
        if client.recommendationEnabled, let url = URL(string: client.origin),
          ["https", "http"].contains(url.scheme ?? "")
        {
          Section("选片前") {
            Link("为我们推荐 / 打开个人电影档案", destination: url)
            Text("双人先投票，再由房主在现有选片入口确认片源、手动播放。不会自动换片。").font(.caption)
          }
        }
        Section("选片后：确认作品与剪辑版本") {
          Text("只绑定本机已经加载的影片。不同清晰度可关联同一版本；剪辑不同请分开记录。").font(.caption)
          TextField("搜索已添加的作品", text: $query)
          ForEach(
            movies.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
          ) { movie in
            Button("\(movie.title)（\(String(movie.year))）") {
              selectedMovie = movie.id
              Task {
                do {
                  editions = try JSONDecoder().decode(
                    [MovieMindEdition].self, from: await client.get("editions?movieId=" + movie.id))
                } catch { client.status = "版本资料暂不可用，请稍后重试" }
              }
            }
          }
          if !selectedMovie.isEmpty && editions.isEmpty {
            Text("先在网页为这部电影建立剪辑版本，并核对准确片长。").font(.caption)
          }
          ForEach(editions) { edition in
            Button("确认 \(edition.label) · \(edition.durationMs/1000) 秒") {
              selectedEdition = edition
            }
          }
        }
        if client.ratingEnabled, !client.boundMovie.isEmpty {
          Section("观影后") {
            Button("确认已看与评分（可跳过）") {
              rating = MovieMindClient.Suggestion(movieId: client.boundMovie, sessionId: "")
            }
          }
        }
        Section("可靠同步") {
          Button("重试待同步内容") { client.retry() }
          Button("读取待同步草稿") {
            Task {
              do {
                drafts = try JSONDecoder().decode(
                  [MovieMindPending].self, from: await client.drafts())
              } catch { client.status = "原待同步文件已保留，请先核对" }
            }
          }
          ForEach(drafts) { item in
            Button(item.conflict ? "并发冲突：核对评分草稿" : "待同步：" + item.path) { conflict = item }
          }
        }
      }.navigationTitle("MovieMind").toolbar { Button("完成") { dismiss() } }
        .task {
          origin = client.origin
          context = model.movieMindSource
          await loadMovies()
        }
        .alert(
          "确认当前影片是同一剪辑版本？",
          isPresented: Binding(
            get: { selectedEdition != nil }, set: { if !$0 { selectedEdition = nil } })
        ) {
          Button("确认绑定本机影片") {
            if let edition = selectedEdition {
              let ok = model.bindMovieMind(
                movie: edition.movieId, edition: edition.id, duration: edition.durationMs,
                source: context)
              if !ok { client.status = "片源已改变、时长不一致或未加载，未绑定；请重新确认" }
            }
            selectedEdition = nil
          }
          Button("取消", role: .cancel) { selectedEdition = nil }
        } message: {
          Text("作品与版本由你确认；本机路径和播放链接不会上传。绑定不会开始播放或改变房间片源。")
        }
        .sheet(item: $rating) { MovieMindRatingView(client: client, suggestion: $0) }
        .sheet(item: $conflict) { MovieMindConflictView(client: client, item: $0) }
    }
  }
  private var loginDisabled: Bool {
    loggingIn || origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
  }
  private func signIn(persistent: Bool) {
    let secret = password
    loggingIn = true
    Task {
      defer { loggingIn = false }
      if await client.login(origin: origin, name: name, password: secret, persistent: persistent) {
        password = ""
        origin = client.origin
        await loadMovies()
      }
    }
  }
  private func loadMovies() async {
    guard !client.origin.isEmpty else { return }
    do {
      movies = try JSONDecoder().decode([MovieMindMovie].self, from: await client.get("movies"))
    } catch { client.status = "MovieMind 暂不可用，播放不受影响" }
  }
}

@MainActor struct MovieMindCompletionBanner: View {
  @ObservedObject var client: MovieMindClient
  @State private var rating: MovieMindClient.Suggestion?
  var body: some View {
    if client.enabled, client.ratingEnabled, let suggestion = client.suggestion {
      HStack {
        Text("可能已看完 · 尚未自动标记或评分").font(.caption)
        Button("确认 / 评分") { rating = suggestion }
        Button("跳过") { client.suggestion = nil }
      }
      .padding(12).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
      .padding()
      .sheet(item: $rating) { MovieMindRatingView(client: client, suggestion: $0) }
    }
  }
}
@MainActor private struct MovieMindRatingView: View {
  @ObservedObject var client: MovieMindClient
  let suggestion: MovieMindClient.Suggestion
  @Environment(\.dismiss) private var dismiss
  @State private var rating = ""
  @State private var comment = ""
  @State private var together = false
  @State private var original = [String: Any]()
  @State private var saving = false
  var body: some View {
    NavigationStack {
      Form {
        Text("作品 ID：" + suggestion.movieId).font(.caption)
        Text("只根据你的确认更新档案。未评分保持空白；技术故障不会自动记为弃看或差评。").font(.caption)
        Picker("个人评分", selection: $rating) {
          Text("未评分").tag("")
          ForEach(0...20, id: \.self) { n in Text(String(Double(n) / 2)).tag(String(Double(n) / 2))
          }
        }
        TextField("可选私人短评", text: $comment, axis: .vertical)
        Toggle("这次是共同观看", isOn: $together)
        Text(client.status).font(.caption)
        Button("确认已看并保存") {
          saving = true
          Task {
            let saved = await client.saveRecord(
              movie: suggestion.movieId, rating: Double(rating), comment: comment,
              together: together, original: original)
            saving = false
            if saved {
              client.completion(session: suggestion.sessionId, decision: "confirmed")
              dismiss()
            }
          }
        }.disabled(saving)
        Button("还未看完") {
          client.completion(session: suggestion.sessionId, decision: "rejected")
          dismiss()
        }
        Button("撤回本次完片确认") {
          client.completion(session: suggestion.sessionId, decision: "withdrawn")
          dismiss()
        }
      }.navigationTitle("观影后评分").toolbar { Button("暂时跳过") { dismiss() } }.task {
        if let data = try? await client.get("records"),
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let row = rows.first(where: { $0["movieId"] as? String == suggestion.movieId })
        {
          original = row
          rating = (row["rating"] as? Double).map { String($0) } ?? ""
          comment = row["comment"] as? String ?? ""
          together = row["together"] as? Bool ?? false
        }
      }
    }
  }
}
@MainActor private struct MovieMindConflictView: View {
  @ObservedObject var client: MovieMindClient
  let item: MovieMindPending
  @Environment(\.dismiss) private var dismiss
  @State private var current = [String: Any]()
  @State private var readable = false
  private var draft: [String: Any] {
    ((try? JSONSerialization.jsonObject(with: item.body)) as? [String: Any])?["record"]
      as? [String: Any] ?? [:]
  }
  var body: some View {
    NavigationStack {
      Form {
        if item.path.hasPrefix("records/") {
          Text(
            "本机评分：\(String(describing:draft["rating"] ?? "未评分"))\n当前评分：\(String(describing:current["rating"] ?? "未评分"))"
          )
          Text(
            "本机短评：\(draft["comment"] as? String ?? "")\n当前短评：\(current["comment"] as? String ?? "")"
          )
          Button("核对后，采用我的评分草稿") {
            Task {
              var merged = current
              if merged.isEmpty {
                merged = ["movieId": draft["movieId"] ?? "", "source": "manual"]
              }
              for key in ["status", "rating", "comment", "together"] { merged[key] = draft[key] }
              let revision = current["revision"] as? Int ?? 0
              do {
                let body = try JSONSerialization.data(withJSONObject: [
                  "record": merged, "expectedRevision": revision, "mutationId": UUID().uuidString,
                ])
                try await client.resolve(id: item.id, body: body)
                dismiss()
              } catch { client.status = "草稿仍保留，稍后重试" }
            }
          }.disabled(!readable)
        } else {
          Text("观影事件会使用原 ID 重试，服务器按区间并集去重。")
          Button("重试") { client.retry() }
        }
        Button("明确丢弃此草稿", role: .destructive) {
          Task {
            try? await client.resolve(id: item.id, body: nil)
            dismiss()
          }
        }
      }.navigationTitle("核对待同步内容").toolbar { Button("保留并关闭") { dismiss() } }.task {
        guard let movie = draft["movieId"] as? String else { return }
        if let data = try? await client.get("records"),
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
          current = rows.first(where: { $0["movieId"] as? String == movie }) ?? [:]
          readable = true
        }
      }
    }
  }
}
