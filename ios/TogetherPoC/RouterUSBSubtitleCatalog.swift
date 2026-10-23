import Foundation
import SwiftUI

enum RouterUSBSubtitleError:LocalizedError {
 case unsupported,unavailable,invalidCatalog,invalidFile
 var errorDescription:String? {
  switch self {
  case .unsupported:return "当前影片没有可识别的路由器 U 盘 HTTP 地址，请从 U 盘影视库选择影片。"
  case .unavailable:return "路由器尚未开放字幕列表，或链接已过期。请刷新影片链接后重试。"
  case .invalidCatalog:return "路由器有字幕记录，但文件地址与当前影片的目录或链接格式不匹配。"
  case .invalidFile:return "字幕下载失败、超出 5MB，或内容不是有效的字幕文件。"
  }
 }
}

struct RouterUSBSubtitleOption:Identifiable {
 let name:String
 let url:URL
 var id:String {url.absoluteString}
}

/// This reader accepts signed /media/usb-* and unsigned /usb-files/ catalogs.
/// Both requests are byte-limited so a router without ?subtitles=1 cannot
/// accidentally transfer a 20-50 GB movie into the iPad.
enum RouterUSBSubtitleCatalog {
 private struct Catalog:Decodable {let subtitles:[Record]}
 private struct Record:Decodable {let name:String;let url:String}
 private static let extensions=Set(["srt","vtt","ass","ssa"])
 private static let maxCatalogBytes=64*1024

 static func catalogURL(for movie:URL?) -> URL? {
  if let movie,let scheme=movie.scheme?.lowercased(),["http","https"].contains(scheme),
     movie.host != nil,movie.pathComponents.count>=3,
     movie.pathComponents[1]=="usb-files",
     var parts=URLComponents(url:movie,resolvingAgainstBaseURL:false),
     (parts.queryItems ?? []).isEmpty {
   parts.queryItems=[URLQueryItem(name:"subtitles",value:"1")]
   return parts.url
  }
  guard let movie,let scheme=movie.scheme?.lowercased(),["http","https"].contains(scheme),
        movie.host != nil,movie.pathComponents.count>=4,
        movie.pathComponents[1]=="media",
        movie.pathComponents[2].hasPrefix("usb-"),
        var components=URLComponents(url:movie,resolvingAgainstBaseURL:false),
        let query=components.queryItems,
        query.contains(where:{$0.name=="sig" && !($0.value ?? "").isEmpty}),
        query.contains(where:{$0.name=="expires" && !($0.value ?? "").isEmpty}) else{return nil}
  components.queryItems=query.filter{$0.name != "subtitles"}+[URLQueryItem(name:"subtitles",value:"1")]
  return components.url
 }
 private enum RouteKind {case unsignedUSB,signedUSB}
 private static func routeKind(of url:URL)->RouteKind? {
  let path=url.pathComponents
  let query=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
  if path.count>=3,path[1]=="usb-files",query.isEmpty {return .unsignedUSB}
  if path.count>=4,path[1]=="media",path[2].hasPrefix("usb-"),
     query.contains(where:{$0.name=="sig" && !($0.value ?? "").isEmpty}),
     query.contains(where:{$0.name=="expires" && !($0.value ?? "").isEmpty}) {
   return .signedUSB
  }
  return nil
 }
 private static func allowed(_ file:URL,movie:URL)->Bool {
  guard file.scheme?.lowercased()==movie.scheme?.lowercased(),
        file.host?.lowercased()==movie.host?.lowercased(),file.port==movie.port,
        extensions.contains(file.pathExtension.lowercased()),
        !file.lastPathComponent.isEmpty,
        let movieRoute=routeKind(of:movie),let fileRoute=routeKind(of:file) else {return false}
  if movieRoute == fileRoute {
   // The same URL representation must stay in the exact same directory.
   return file.pathComponents.dropLast()==movie.pathComponents.dropLast()
  }
  // The router can advertise a directly accessible /usb-files/ sidecar for a
  // previously signed /media/usb-* movie (or the reverse) during migration.
  // The catalog itself comes from this film's ?subtitles=1 endpoint. Retain
  // the origin, extension and per-representation access checks above.
  return true
 }
 static func decodeCatalog(_ data:Data,movie:URL)throws->[RouterUSBSubtitleOption] {
  guard let catalog=try? JSONDecoder().decode(Catalog.self,from:data),
        catalog.subtitles.count<=100 else {throw RouterUSBSubtitleError.invalidCatalog}
  var results:[RouterUSBSubtitleOption]=[]
  var names=Set<String>()
  for record in catalog.subtitles {
   guard !record.name.isEmpty,record.name==URL(fileURLWithPath:record.name).lastPathComponent,
         !record.name.contains("\\"),!record.name.contains(".."),
         let file=URL(string:record.url,relativeTo:movie)?.absoluteURL,
         allowed(file,movie:movie),file.lastPathComponent==record.name else {continue}
   if names.insert(file.absoluteString).inserted {
    results.append(RouterUSBSubtitleOption(name:record.name,url:file))
   }
  }
  if !catalog.subtitles.isEmpty && results.isEmpty {throw RouterUSBSubtitleError.invalidCatalog}
  return results.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
 }
 static func list(for movie:URL) async throws->[RouterUSBSubtitleOption] {
  guard let url=catalogURL(for:movie) else {throw RouterUSBSubtitleError.unsupported}
  return try await Task.detached(priority:.userInitiated) {
   var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
   request.setValue("application/json",forHTTPHeaderField:"Accept")
   guard let (data,response)=FilmMaterialRangeRequest(limit:maxCatalogBytes,expectedStatus:200,followRedirects:false)
    .fetch(request:request,configuration:.ephemeral),
         response.value(forHTTPHeaderField:"Content-Type")?.lowercased().contains("application/json")==true else {
    throw RouterUSBSubtitleError.unavailable
   }
   return try decodeCatalog(data,movie:movie)
  }.value
 }
 static func read(_ option:RouterUSBSubtitleOption,for movie:URL) async throws->SubtitleDocument {
  guard allowed(option.url,movie:movie) else {throw RouterUSBSubtitleError.invalidFile}
  return try await Task.detached(priority:.userInitiated) {
   var request=URLRequest(url:option.url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30)
   request.setValue("text/plain, application/octet-stream",forHTTPHeaderField:"Accept")
   guard let (data,_)=FilmMaterialRangeRequest(limit:SubtitleParser.maxBytes+1,expectedStatus:200,followRedirects:false)
    .fetch(request:request,configuration:.ephemeral) else {throw RouterUSBSubtitleError.invalidFile}
   return try SubtitleParser.parse(data,extension:option.url.pathExtension)
  }.value
 }
}

@MainActor struct RouterUSBSubtitlePicker:View {
 let movie:URL?
 let onPick:(RouterUSBSubtitleOption)->Void
 let onClose:()->Void
 @State private var entries:[RouterUSBSubtitleOption]=[]
 @State private var loading=false
 @State private var status="正在查找同目录外挂字幕…"

 var body:some View {
  NavigationStack {
   List {
    Section {
     Text("查找当前 U 盘电影同目录的 SRT / VTT / ASS / SSA 字幕，优先同名字幕，也支持带版本后缀的 ASS 文件。只读取字幕内容，不下载电影。")
      .font(.footnote).foregroundStyle(.secondary)
     if loading {ProgressView("正在读取字幕列表…")}
     else if entries.isEmpty {Text(status).font(.footnote).foregroundStyle(.orange)}
     else {ForEach(entries) {entry in
      Button {onPick(entry)} label:{
       Label(entry.name,systemImage:"captions.bubble").lineLimit(3)
      }.accessibilityIdentifier("router-subtitle-option")
     }}
    }
    Section {Button("重新扫描 U 盘字幕") {Task {await refresh()}}.disabled(loading)}
   }
   .navigationTitle("从路由器 U 盘选择字幕")
   .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("关闭",action:onClose)}}
   .task {await refresh()}
  }.preferredColorScheme(.dark)
 }
 private func refresh() async {
  guard !loading else{return}
  guard let movie else {status="请先选择 U 盘电影。";return}
  loading=true;defer{loading=false}
  do {
   let found=try await RouterUSBSubtitleCatalog.list(for:movie)
   guard !Task.isCancelled else{return}
   entries=found
   status=found.isEmpty ? "当前影片目录没有可选字幕。请确认文件位于同一文件夹。" : "共找到 \(found.count) 个字幕"
  } catch {
   entries=[]
   status=error.localizedDescription
  }
 }
}
