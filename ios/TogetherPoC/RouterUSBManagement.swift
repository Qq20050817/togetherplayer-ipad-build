import Foundation
import SwiftUI

struct RouterUSBEntry: Decodable, Identifiable {
 let name: String
 let path: String
 let directory: Bool
 let bytes: Int64
 let version: String?
 var id: String {path}
}

private struct RouterUSBResponse: Decodable {
 var csrf: String?
 var authenticated: Bool?
 var deleteAvailable: Bool?
 var items: [RouterUSBEntry]?
 var hasMore: Bool?
 var deleted: Bool?
 var path: String?
 var error: String?
}

private final class USBManagementNoRedirect: NSObject, URLSessionTaskDelegate {
 func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {completionHandler(nil)}
}

@MainActor final class RouterUSBManagement: ObservableObject {
 @Published private(set) var items: [RouterUSBEntry] = []
 @Published private(set) var busy = false
 @Published private(set) var authenticated = false
 @Published private(set) var deleteAvailable = false
 @Published private(set) var folder = ""
 @Published private(set) var page = 0
 @Published private(set) var hasMore = false
 @Published private(set) var status = "连接家里的 Wi-Fi，使用 U 盘影片管理密码登录。"
 private let base = URL(string: "http://192.168.31.1:49186")!
 private let session: URLSession
 private var csrf = ""
 init(session: URLSession? = nil) {
  if let session {self.session = session; return}
  let config = URLSessionConfiguration.ephemeral
  config.timeoutIntervalForRequest = 20
  config.timeoutIntervalForResource = 30
  self.session = URLSession(configuration: config, delegate: USBManagementNoRedirect(), delegateQueue: nil)
 }
 private func request(_ path: String, query: [URLQueryItem] = [], body: [String: String]? = nil) async throws -> RouterUSBResponse {
  var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
  if !query.isEmpty {components.queryItems = query}
  var req = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
  if let body {
   req.httpMethod = "POST"
   req.httpBody = try JSONEncoder().encode(body)
   req.setValue("application/json", forHTTPHeaderField: "Content-Type")
   req.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
   req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
  }
  let (data, response) = try await session.data(for: req)
  guard let http = response as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else {throw URLError(.badServerResponse)}
  let result = try JSONDecoder().decode(RouterUSBResponse.self, from: data)
  if let token = result.csrf {csrf = token}
  guard (200..<300).contains(http.statusCode) else {
   if http.statusCode == 401 {authenticated = false; items = []}
   let messages = ["authentication_failed":"U 盘管理密码不正确。", "login_required":"请重新登录。", "delete_not_enabled":"路由器尚未启用删除功能。", "usb_read_only":"U 盘当前为只读，无法删除；需要维护者检查后启用写入。", "file_changed":"文件已变化或不存在，请刷新后重新选择。", "delete_permission_denied":"路由器没有此文件的删除权限。", "usb_not_mounted":"U 盘尚未挂载。", "usb_identity_mismatch":"U 盘身份核对失败。", "eject_in_progress":"正在安全弹出，请稍后再试。", "too_many_attempts":"密码尝试过多，请稍后再试。"]
   throw NSError(domain: "RouterUSB", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: messages[result.error ?? ""] ?? "路由器未完成操作，请刷新核对。"])
  }
  return result
 }
 func login(password: String) async {
  guard !busy else {return}
  busy = true
  defer {busy = false}
  do {
   let state = try await request("api/session")
   deleteAvailable = state.deleteAvailable == true
   if state.authenticated != true {
    let login = try await request("api/login", body: ["password": password])
    guard login.authenticated == true else {throw URLError(.userAuthenticationRequired)}
   }
   authenticated = true
   try await load(folder: "", page: 0)
  } catch {status = error.localizedDescription}
 }
 private func load(folder: String, page: Int) async throws {
  let result = try await request("api/list", query: [URLQueryItem(name: "path", value: folder), URLQueryItem(name: "page", value: String(page))])
  guard let entries = result.items else {throw URLError(.cannotParseResponse)}
  items = entries; self.folder = folder; self.page = page; hasMore = result.hasMore == true
  status = deleteAvailable ? "删除的是 U 盘原文件，无法在 App 内撤销。" : "路由器尚未启用删除功能；可以浏览文件。"
 }
 func browse(_ folder: String, page: Int = 0) async {
  guard !busy else {return}; busy = true; defer {busy = false}
  do {try await load(folder: folder, page: page)} catch {status = error.localizedDescription}
 }
 func delete(_ entry: RouterUSBEntry) async {
  guard !busy, authenticated, deleteAvailable, !entry.directory, let version = entry.version else {return}
  busy = true; defer {busy = false}
  do {
   let result = try await request("api/delete", body: ["path": entry.path, "version": version])
   guard result.deleted == true, result.path == entry.path else {throw URLError(.badServerResponse)}
   items.removeAll {$0.path == entry.path}
   status = "已删除并核验：\(entry.name)"
  } catch {status = "\(error.localizedDescription) 未确认删除成功，请刷新核对。"}
 }
}

@MainActor struct RouterUSBManagementView: View {
 @StateObject private var manager = RouterUSBManagement()
 @State private var password = ""
 @State private var selected: RouterUSBEntry?
 @Environment(\.dismiss) private var dismiss
 var body: some View {
  NavigationStack {
   List {
    Section {
     Text(manager.status).font(.callout).accessibilityIdentifier("usb-management-status")
     Text("删除会影响所有使用此文件的设备。请先停止播放。当前仅支持逐个删除视频，不删除文件夹及字幕。").font(.caption).foregroundStyle(.secondary)
    }
    if !manager.authenticated {
     Section("U 盘影片管理密码") {
      SecureField("管理密码", text: $password).textContentType(.password)
      Button("登录") {let value = password; password = ""; Task {await manager.login(password: value)}}.disabled(manager.busy || password.isEmpty)
     }
    } else {
     Section(manager.folder.isEmpty ? "U 盘影片目录" : manager.folder) {
      if !manager.folder.isEmpty {
       Button("上一级") {let parent = manager.folder.split(separator: "/").dropLast().joined(separator: "/"); Task {await manager.browse(parent)}}
      }
      ForEach(manager.items) {entry in
       HStack {
        if entry.directory {
         Button {Task {await manager.browse(entry.path)}} label: {Label(entry.name, systemImage: "folder")}
        } else {
         VStack(alignment: .leading) {
          Text(entry.name)
          Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
         }
         Spacer()
         Button(role: .destructive) {selected = entry} label: {Image(systemName: "trash")}
          .buttonStyle(.borderless).accessibilityLabel("删除 U 盘原文件：\(entry.name)")
          .disabled(!manager.deleteAvailable || entry.version == nil)
        }
       }
      }
      if manager.page > 0 {Button("上一页") {Task {await manager.browse(manager.folder, page: manager.page - 1)}}}
      if manager.hasMore {Button("下一页") {Task {await manager.browse(manager.folder, page: manager.page + 1)}}}
     }.disabled(manager.busy)
    }
    if manager.busy {ProgressView("正在处理…")}
   }
   .navigationTitle("管理 U 盘原文件")
   .toolbar {
    ToolbarItem(placement: .topBarLeading) {Button("刷新") {Task {await manager.browse(manager.folder, page: manager.page)}}.disabled(manager.busy || !manager.authenticated)}
    ToolbarItem(placement: .topBarTrailing) {Button("完成") {dismiss()}.disabled(manager.busy)}
   }
   .alert("删除 U 盘原文件？", isPresented: Binding(get: {selected != nil}, set: {if !$0 {selected = nil}}), presenting: selected) {entry in
    Button("永久删除", role: .destructive) {Task {await manager.delete(entry)}; selected = nil}
    Button("取消", role: .cancel) {selected = nil}
   } message: {entry in Text("\(entry.path)\n\(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file))\n所有设备将无法再读取此文件，App 内无法撤销。")}
   .interactiveDismissDisabled(manager.busy)
  }.preferredColorScheme(.dark)
 }
}
