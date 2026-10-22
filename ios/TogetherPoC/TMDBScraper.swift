import Foundation
import SwiftUI
import Security

// TMDB API Read Access Token stays in the iPad Keychain and is never bundled in the IPA.
enum TMDBKeychain {
 private static let service = "dev.together.poc.tmdb"
 private static let account = "read-access-token"
 static func read() -> String? {
  let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,
    kSecAttrService as String:service,kSecAttrAccount as String:account,
    kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
  var result:CFTypeRef?
  guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess,
    let data=result as? Data,let token=String(data:data,encoding:.utf8) else{return nil}
  return token
 }
 @discardableResult static func save(_ value:String)->Bool {
  let token=value.trimmingCharacters(in:.whitespacesAndNewlines)
  guard token.count>=40,token.count<=512,token.range(of:#"^[A-Za-z0-9._\-]+$"#,options:.regularExpression) != nil else{return false}
  let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,
    kSecAttrService as String:service,kSecAttrAccount as String:account]
  let data=Data(token.utf8)
  let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
  if status == errSecSuccess {return true}
  guard status == errSecItemNotFound else{return false}
  var add=query
  add[kSecValueData as String]=data
  add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  return SecItemAdd(add as CFDictionary,nil)==errSecSuccess
 }
 static func clear() {
  let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
    kSecAttrService as String:service,kSecAttrAccount as String:account]
  SecItemDelete(query as CFDictionary)
 }
}

struct TMDBCandidate:Decodable,Identifiable,Hashable {
 let id:Int
 let title:String?
 let name:String?
 let originalTitle:String?
 let originalName:String?
 let releaseDate:String?
 let firstAirDate:String?
 let posterPath:String?
 var isTV:Bool=false
 enum CodingKeys:String,CodingKey {
  case id,title,name,originalTitle,originalName,releaseDate,firstAirDate,posterPath
 }
 var shownTitle:String {title ?? name ?? originalTitle ?? originalName ?? "未知影片"}
 var original:String {originalTitle ?? originalName ?? ""}
 var year:Int? {
  let date=releaseDate ?? firstAirDate ?? ""
  return Int(date.prefix(4))
 }
 var posterURL:URL? {TMDBImage.url(posterPath)}
}

enum TMDBImage {
 static func url(_ path:String?)->URL? {
  guard let path,path.hasPrefix("/"),path.count<180,
   path.range(of:#"^/[A-Za-z0-9._-]+\.(jpg|jpeg|png|webp)$"#,options:.regularExpression) != nil else{return nil}
  return URL(string:"https://image.tmdb.org/t/p/w500"+path)
 }
}

struct TMDBInfo:Codable {
 let id:Int
 let isTV:Bool
 let title:String
 let originalTitle:String
 let year:Int?
 let overview:String
 let posterPath:String?
 let backdropPath:String?
 let genres:[String]
 let cast:[String]
 let director:[String]
 let runtime:Int?
 let voteAverage:Double?
 var posterURL:URL? {TMDBImage.url(posterPath)}
 var backdropURL:URL? {TMDBImage.url(backdropPath)}
 var sourceURL:URL? {URL(string:"https://www.themoviedb.org/"+(isTV ? "tv/" : "movie/")+String(id))}
}

enum TMDBMatcher {
 static func aliases(for movie:USBMovie)->[String] {
  var terms=[movie.posterSearchTitle,FilmTaste.clean(movie.name)]
  if let film=movie.matchedFilm {terms += [film.title]+film.aliases}
  var unique=Set<String>()
  return terms.filter {
   let key=FilmTaste.key($0)
   return key.count>=3 && key.count<=85 && unique.insert(key).inserted
  }
 }
 static func score(_ candidate:TMDBCandidate,movie:USBMovie)->Int {
  if let year=(movie.releaseYear ?? movie.matchedFilm?.year) {
   guard let found=candidate.year,abs(found-year)<=1 else{return -1}
  }
  let keys=aliases(for:movie).map(FilmTaste.key)
  let names=[candidate.shownTitle,candidate.original].map(FilmTaste.key)
  guard names.contains(where:keys.contains) else{return -1}
  return 100+(candidate.year == (movie.releaseYear ?? movie.matchedFilm?.year) && (movie.releaseYear ?? movie.matchedFilm?.year) != nil ? 15 : 0)
 }
 static func exactMatch(_ rows:[TMDBCandidate],movie:USBMovie)->TMDBCandidate? {
  let ranked=rows.map{($0,score($0,movie:movie))}.filter{$0.1>=100}.sorted{$0.1>$1.1}
  guard let first=ranked.first else{return nil}
  // Similar titles and remakes must go through manual confirmation.
  guard ranked.count==1 || first.1>ranked[1].1 else{return nil}
  return first.0
 }
}

private struct TMDBSearchEnvelope:Decodable {let results:[TMDBCandidate]}
private struct TMDBDetailResponse:Decodable {
 let id:Int
 let title:String?
 let name:String?
 let originalTitle:String?
 let originalName:String?
 let releaseDate:String?
 let firstAirDate:String?
 let overview:String?
 let posterPath:String?
 let backdropPath:String?
 let runtime:Int?
 let episodeRunTime:[Int]?
 let voteAverage:Double?
 let genres:[Genre]?
 let credits:Credits?
 struct Genre:Decodable {let name:String}
 struct Credits:Decodable {
  let cast:[Cast]?
  let crew:[Crew]?
  struct Cast:Decodable {let name:String}
  struct Crew:Decodable {let name:String;let job:String}
 }
}

actor TMDBPacer {
 static let shared=TMDBPacer()
 private var next=Date.distantPast
 func pause() async throws {
  let now=Date()
  let scheduled=max(now,next)
  next=scheduled.addingTimeInterval(0.65)
  let delay=scheduled.timeIntervalSince(now)
  if delay>0 {try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))}
 }
}

enum TMDBAPI {
 enum Failure:LocalizedError {
  case unauthorized,rateLimited,http(Int),oversized,invalidResponse
  var errorDescription:String? {
   switch self {
   case .unauthorized:return "TMDB 授权失败，请检查读取令牌"
   case .rateLimited:return "TMDB 请求过于频繁，请稍后重试"
   case .http(let status):return "TMDB 请求失败（HTTP \(status)）"
   case .oversized:return "TMDB 返回数据过大"
   case .invalidResponse:return "TMDB 数据格式异常"
   }
  }
 }
 static func request<T:Decodable>(_ path:String,query:[URLQueryItem],token:String) async throws -> T {
  try await TMDBPacer.shared.pause()
  var url=URLComponents()
  url.scheme="https";url.host="api.themoviedb.org";url.path="/3/"+path
  url.queryItems=query+[URLQueryItem(name:"language",value:"zh-CN")]
  guard let target=url.url else{throw Failure.invalidResponse}
  var req=URLRequest(url:target,cachePolicy:.returnCacheDataElseLoad,timeoutInterval:12)
  req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
  req.setValue("application/json",forHTTPHeaderField:"Accept")
  let (data,response)=try await URLSession.shared.data(for:req)
  guard let http=response as? HTTPURLResponse else{throw Failure.invalidResponse}
  switch http.statusCode {
  case 200:break
  case 401,403:throw Failure.unauthorized
  case 429:throw Failure.rateLimited
  default:throw Failure.http(http.statusCode)
  }
  guard data.count<=2_000_000 else{throw Failure.oversized}
  let decoder=JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  return try decoder.decode(T.self,from:data)
 }
 static func search(_ text:String,isTV:Bool,token:String) async throws -> [TMDBCandidate] {
   let query=text.trimmingCharacters(in:.whitespacesAndNewlines)
   guard (2...100).contains(query.count) else{return []}
   let response:TMDBSearchEnvelope=try await request(
    "search/"+(isTV ? "tv" : "movie"),
    query:[URLQueryItem(name:"query",value:query),URLQueryItem(name:"include_adult",value:"false"),
      URLQueryItem(name:"page",value:"1")],token:token)
   return response.results.prefix(20).map {
    var row=$0;row.isTV=isTV;return row
   }
 }
 static func detail(_ row:TMDBCandidate,token:String) async throws -> TMDBInfo {
  let record:TMDBDetailResponse=try await request(
    (row.isTV ? "tv/" : "movie/")+String(row.id),
    query:[URLQueryItem(name:"append_to_response",value:"credits")],token:token)
  let raw=record.title ?? record.name ?? row.shownTitle
  let filmYear=Int((record.releaseDate ?? record.firstAirDate ?? "").prefix(4))
  return TMDBInfo(id:record.id,isTV:row.isTV,title:raw,
   originalTitle:record.originalTitle ?? record.originalName ?? row.original,
   year:filmYear,overview:record.overview ?? "",posterPath:record.posterPath,
   backdropPath:record.backdropPath,genres:(record.genres ?? []).map(\.name),
   cast:Array((record.credits?.cast ?? []).prefix(7).map(\.name)),
   director:(record.credits?.crew ?? []).filter{$0.job=="Director"}.map(\.name),
   runtime:record.runtime ?? record.episodeRunTime?.first,voteAverage:record.voteAverage)
 }
}

@MainActor final class TMDBCatalogStore:ObservableObject {
 @Published private(set) var records:[String:TMDBInfo]=[:]
 @Published private(set) var choices:[String:[TMDBCandidate]]=[:]
 @Published private(set) var messages:[String:String]=[:]
 @Published private(set) var busy:Set<String>=[]
 @Published private(set) var configured=TMDBKeychain.read() != nil
 @Published private(set) var generation=0
 private var attempted:[String:Date]=[:]
 private var cacheURL:URL? {
  guard let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first else{return nil}
  return folder.appendingPathComponent("tmdb-library-v1.json")
 }
 init() {
  if let file=cacheURL,let data=try? Data(contentsOf:file),
    let saved=try? JSONDecoder().decode([String:TMDBInfo].self,from:data) {records=saved}
 }
 func storeToken(_ value:String)->Bool {
  guard TMDBKeychain.save(value) else{return false}
  configured=true;attempted.removeAll();generation+=1
  return true
 }
 func removeToken() {
  TMDBKeychain.clear();configured=false;attempted.removeAll();generation+=1
 }
 func title(for movie:USBMovie)->String {
  guard let info=records[movie.id] else{return movie.displayTitle}
  let name=info.title.range(of:#"\p{Han}"#,options:.regularExpression) != nil ?
    info.title : (movie.matchedFilm?.title ?? info.title)
  return name+(info.year.map{" (\($0))"} ?? "")
 }
 func info(for movie:USBMovie)->TMDBInfo? {records[movie.id]}
 func cover(for movie:USBMovie)->URL? {records[movie.id]?.posterURL}
 func lookup(_ movie:USBMovie,force:Bool=false) async {
  guard configured,let token=TMDBKeychain.read(),!busy.contains(movie.id) else{return}
  if !force && records[movie.id] != nil {return}
  if !force,let last=attempted[movie.id],Date().timeIntervalSince(last)<1800{return}
  busy.insert(movie.id);attempted[movie.id]=Date()
  defer{busy.remove(movie.id)}
  do {
   var all:[TMDBCandidate]=[]
   for term in TMDBMatcher.aliases(for:movie).prefix(3) where !Task.isCancelled {
    let rows=try await TMDBAPI.search(term,isTV:movie.isEpisode,token:token)
    for row in rows where !all.contains(where:{$0.id==row.id && $0.isTV==row.isTV}) {all.append(row)}
    if let exact=TMDBMatcher.exactMatch(all,movie:movie) {
     let info=try await TMDBAPI.detail(exact,token:token)
     records[movie.id]=info;choices[movie.id]=nil;messages[movie.id]=nil
     persist()
     return
    }
   }
   choices[movie.id]=Array(all.prefix(20))
   messages[movie.id]=all.isEmpty ? "未检索到相关影片，可以手动搜索" : "存在同名或版本差异，请手动确认匹配"
  } catch {
   messages[movie.id]=error.localizedDescription
  }
 }
 func searchManually(_ movie:USBMovie,text:String) async {
  guard let token=TMDBKeychain.read(),!busy.contains(movie.id) else{return}
  busy.insert(movie.id);defer{busy.remove(movie.id)}
  do {
   let film=try await TMDBAPI.search(text,isTV:movie.isEpisode,token:token)
   let tv=try await TMDBAPI.search(text,isTV:!movie.isEpisode,token:token)
   choices[movie.id]=Array((film+tv).prefix(30))
   messages[movie.id]=choices[movie.id]?.isEmpty == true ? "没有搜索结果，请换个名称" : "请选择正确的影片或剧集"
  } catch {messages[movie.id]=error.localizedDescription}
 }
 func choose(_ row:TMDBCandidate,movie:USBMovie) async {
  guard let token=TMDBKeychain.read(),!busy.contains(movie.id) else{return}
  busy.insert(movie.id);defer{busy.remove(movie.id)}
  do {
   let info=try await TMDBAPI.detail(row,token:token)
   records[movie.id]=info;choices[movie.id]=nil;messages[movie.id]=nil
   persist()
  } catch {messages[movie.id]=error.localizedDescription}
 }
 private func persist() {
  guard let url=cacheURL,let data=try? JSONEncoder().encode(records) else{return}
  try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
  try? data.write(to:url,options:.atomic)
 }
}

@MainActor struct TMDBSettingsView:View {
 @ObservedObject var catalog:TMDBCatalogStore
 @Environment(\.dismiss) private var dismiss
 @State private var token=""
 @State private var failed=false
 var body:some View {
  NavigationStack {
   Form {
    Section("TMDB 在线刮削") {
     Label(catalog.configured ? "已配置读取令牌" : "尚未配置读取令牌",
      systemImage:catalog.configured ? "checkmark.shield" : "key")
     SecureField("粘贴 API Read Access Token",text:$token)
      .textInputAutocapitalization(.never).autocorrectionDisabled()
     Button("保存并启用自动刮削") {
      failed = !catalog.storeToken(token)
      if !failed {token="";dismiss()}
     }.disabled(token.isEmpty)
     if failed {Text("保存失败：请填写 TMDB 的 API Read Access Token").foregroundStyle(.orange)}
     Link("去 TMDB 获取读取令牌",destination:URL(string:"https://www.themoviedb.org/settings/api")!)
     if catalog.configured {
      Button("移除读取令牌",role:.destructive) {catalog.removeToken()}
     }
    }
    Section("说明与数据来源") {
     Text("启用后会联网查询影片名称、海报、简介及演职员。搜索词会发送至 TMDB，结果缓存到本机。资料缺失或有歧义时可手动匹配。")
     Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
      .font(.caption)
     Link("TMDB / The Movie Database",destination:URL(string:"https://www.themoviedb.org")!)
    }
   }
   .navigationTitle("在线刮削设置")
   .toolbar {Button("完成"){dismiss()}}
  }.preferredColorScheme(.dark)
 }
}

@MainActor struct TMDBDetailView:View {
 let movie:USBMovie
 @ObservedObject var catalog:TMDBCatalogStore
 @Environment(\.dismiss) private var dismiss
 @State private var query=""
 var body:some View {
  NavigationStack {
   ScrollView {
    VStack(alignment:.leading,spacing:16) {
     if let detail=catalog.info(for:movie) {
      HStack(alignment:.top,spacing:16) {
       AsyncImage(url:detail.posterURL) {image in image.resizable().scaledToFill()}
        placeholder:{Image(systemName:"film").font(.largeTitle)}
        .frame(width:115,height:165).clipped().clipShape(RoundedRectangle(cornerRadius:10))
       VStack(alignment:.leading,spacing:6) {
        Text(catalog.title(for:movie)).font(.title3.bold())
        Text(detail.originalTitle).foregroundStyle(.secondary)
        Text([detail.year.map(String.init),detail.runtime.map{"\($0) 分钟"},detail.genres.joined(separator:" / ")]
         .compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption)
        if let rating=detail.voteAverage {Text(String(format:"TMDB %.1f / 10",rating)).foregroundStyle(.yellow)}
       }
      }
      if !detail.overview.isEmpty {Text("剧情简介").font(.headline);Text(detail.overview)}
      if !detail.director.isEmpty {Text("导演："+detail.director.joined(separator:"、"))}
      if !detail.cast.isEmpty {Text("演员："+detail.cast.joined(separator:"、"))}
      if let url=detail.sourceURL {Link("查看 TMDB 条目",destination:url)}
     } else {
      Text("当前没有已确认的在线资料").foregroundStyle(.secondary)
     }
     HStack {
      TextField("输入影片中文名、英文名或原名",text:$query)
       .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
      Button("搜索") {Task {await catalog.searchManually(movie,text:query)}}
       .disabled(query.trimmingCharacters(in:.whitespaces).count<2)
     }
     Button("重新自动刮削") {Task {await catalog.lookup(movie,force:true)}}
      .disabled(!catalog.configured || catalog.busy.contains(movie.id))
     if catalog.busy.contains(movie.id) {ProgressView("正在查询 TMDB…")}
     if let message=catalog.messages[movie.id] {Text(message).font(.caption).foregroundStyle(.orange)}
     if let options=catalog.choices[movie.id],!options.isEmpty {
      Text("手动选择正确版本").font(.headline)
      ForEach(options,id:\.self) {entry in
       Button {
        Task {await catalog.choose(entry,movie:movie)}
       } label:{
        HStack(spacing:10) {
         AsyncImage(url:entry.posterURL) {image in image.resizable().scaledToFit()}
          placeholder:{Image(systemName:"film")}
          .frame(width:42,height:60)
         VStack(alignment:.leading) {
          Text(entry.shownTitle).font(.subheadline.bold())
          Text([entry.original,entry.year.map(String.init) ?? "",entry.isTV ? "剧集" : "电影"]
           .filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
         }
         Spacer()
         Image(systemName:"checkmark.circle")
        }
       }.buttonStyle(.plain).disabled(catalog.busy.contains(movie.id))
      }
     }
     Divider()
     Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
      .font(.caption2).foregroundStyle(.secondary)
    }.padding()
   }
   .navigationTitle("影片资料")
   .toolbar {Button("完成"){dismiss()}}
   .task {await catalog.lookup(movie)}
  }.preferredColorScheme(.dark)
 }
}
