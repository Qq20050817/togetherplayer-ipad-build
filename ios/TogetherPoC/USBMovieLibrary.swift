import Foundation
import SwiftUI

struct USBMovie: Decodable, Identifiable {
 let name: String
 let path: String
 let size: Int64
 let url: String
 var id: String { path }
}

enum USBMovieLibrary {
 static let endpoint = URL(string:"http://usb-media.xiaokai123.de5.net:49185/usb-library.json")!
 private struct Index: Decodable { let version: Int; let items: [USBMovie] }

 static func list() async throws -> [USBMovie] {
  var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 22)
  request.setValue("application/json", forHTTPHeaderField: "Accept")
  let (data,response) = try await URLSession.shared.data(for: request)
  guard let http=response as? HTTPURLResponse, http.statusCode==200,
        data.count<=2*1024*1024 else {throw URLError(.badServerResponse)}
  let index = try JSONDecoder().decode(Index.self,from:data)
  guard index.version==1, index.items.count<=5000 else {throw URLError(.cannotParseResponse)}
  return index.items.filter{ playableURL($0.url) != nil }
 }

 static func playableURL(_ path:String) -> URL? {
  guard path.hasPrefix("/usb-files/"),!path.contains("?"),!path.contains("#"),
        let url=URL(string:path,relativeTo:endpoint)?.absoluteURL,
        url.host==endpoint.host,url.port==endpoint.port,
        url.scheme==endpoint.scheme,
        ["mkv","mp4","m4v","mov","webm","avi","ts"].contains(url.pathExtension.lowercased()) else {return nil}
  return url
 }
}

@MainActor struct USBMovieBrowser: View {
 let select:(USBMovie,URL)->Void
 let close:()->Void
 @State private var movies:[USBMovie]=[]
 @State private var loading=false
 @State private var error=""
 @State private var search=""

 private var filtered:[USBMovie] {
  guard !search.isEmpty else {return movies}
  return movies.filter{$0.name.localizedStandardContains(search)||$0.path.localizedStandardContains(search)}
 }

 var body:some View {
  NavigationStack {
   List {
    Section {
     if loading {ProgressView("正在扫描路由器 U 盘影片…")}
     if !error.isEmpty {Text(error).foregroundStyle(.orange)}
     if !loading && error.isEmpty && movies.isEmpty {
      Text("电影目录暂无可播放视频。").foregroundStyle(.secondary)
     }
     ForEach(filtered) {movie in
      if let url=USBMovieLibrary.playableURL(movie.url) {
       Button {select(movie,url)} label:{
        VStack(alignment:.leading,spacing:4) {
         Label(movie.name,systemImage:"film").lineLimit(2)
         Text("\(movie.path) · \(ByteCountFormatter.string(fromByteCount:movie.size,countStyle:.file))")
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical,4)
       }.accessibilityIdentifier("usb-movie-option")
      }
     }
    } header:{Text("电影（\(filtered.count)）")}
    footer:{Text("影片保存在路由器 U 盘，使用不带签名的 HTTP 直链播放。仅 iPad 房主可以设置房间影片。")}
   }
   .searchable(text:$search,prompt:"搜索电影文件名")
   .navigationTitle("U盘影视库")
   .toolbar {
    ToolbarItem(placement:.topBarLeading){Button("刷新"){Task {await refresh()}}.disabled(loading)}
    ToolbarItem(placement:.topBarTrailing){Button("关闭",action:close)}
   }
   .task {await refresh()}
  }.preferredColorScheme(.dark)
 }

 private func refresh() async {
  guard !loading else{return}
  loading=true
  defer{loading=false}
  do {movies=try await USBMovieLibrary.list();error=""}
  catch {self.error="获取影片目录失败：\(error.localizedDescription)"}
 }
}
