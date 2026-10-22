import Foundation
import SwiftUI
import Combine

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
 @StateObject private var posters=USBPosterStore()
 @StateObject private var tmdb=TMDBCatalogStore()
 @State private var tmdbSettings=false
 @State private var detailMovie:USBMovie?

 private var filtered:[USBMovie] {
  guard !search.isEmpty else {return movies}
  return movies.filter{$0.name.localizedStandardContains(search)||$0.path.localizedStandardContains(search)||tmdb.title(for:$0).localizedStandardContains(search)}
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
        HStack(alignment:.center,spacing:12) {
         USBPosterTile(movie:movie,posters:posters,tmdb:tmdb,width:60,height:82)
         VStack(alignment:.leading,spacing:5) {
          Text(tmdb.title(for:movie)).font(.subheadline.bold()).lineLimit(2)
          Text(movie.isEpisode ? "电视剧 / 动画剧集" : "电影").font(.caption2).foregroundStyle(.cyan)
          Text(ByteCountFormatter.string(fromByteCount:movie.size,countStyle:.file))
           .font(.caption).foregroundStyle(.secondary)
          if let info=tmdb.info(for:movie) {Text(info.genres.prefix(2).joined(separator:" / ")).font(.caption2).foregroundStyle(.secondary)}
         }
        }.padding(.vertical,4)
       }.accessibilityIdentifier("usb-movie-option")
       Button {detailMovie=movie} label:{Image(systemName:"info.circle")}
        .accessibilityLabel("查看影片资料")
      }
     }
    } header:{Text("电影（\(filtered.count)）")}
    footer:{Text("影片保存在路由器 U 盘，使用不带签名的 HTTP 直链播放。仅 iPad 房主可以设置房间影片。")}
   }
   .searchable(text:$search,prompt:"搜索电影文件名")
   .navigationTitle("U盘影视库")
   .toolbar {
    ToolbarItem(placement:.topBarLeading){Button("刷新"){Task {await refresh()}}.disabled(loading)}
    ToolbarItem(placement:.topBarTrailing){Button("TMDB"){tmdbSettings=true}}
    ToolbarItem(placement:.topBarTrailing){Button("关闭",action:close)}
   }
   .task {await refresh()}
   .sheet(isPresented:$tmdbSettings){TMDBSettingsView(catalog:tmdb)}
   .sheet(item:$detailMovie){TMDBDetailView(movie:$0,catalog:tmdb)}
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

// Reuse the film identities already shipped for watch history. This keeps
// localized titles and cover matching independent of file URLs.
enum USBFilmMetadata {
 static let catalog:[WatchFilm] = {
  guard let url=Bundle.main.url(forResource:"film-catalog",withExtension:"json"),
   let data=try? Data(contentsOf:url),
   let films=try? JSONDecoder().decode([WatchFilm].self,from:data) else {return []}
  return films
 }()
 static func film(for movie:USBMovie)->WatchFilm? {
  guard !movie.isEpisode else{return nil}
  return FilmTaste.match(movie.name,catalog:catalog)
 }
}

enum USBArtworkMatch {
 static func key(_ raw:String)->String {FilmTaste.key(raw)}
 static func accepts(movie:USBMovie,title:String,releaseDate:String?)->Bool {
  let aliases=[movie.posterSearchTitle]+(movie.matchedFilm.map{[$0.title]+$0.aliases} ?? [])
  let candidate=key(title)
  guard !candidate.isEmpty,aliases.contains(where:{key($0)==candidate}) else{return false}
  if let expected=movie.releaseYear {
   guard let date=releaseDate,let found=Int(date.prefix(4)),abs(found-expected)<=1 else{return false}
  }
  return true
 }
}

// A router file is a transient catalog entry, not a locally downloaded movie.
// Presentation metadata never alters its original play URL or room identity.
extension USBMovie {
 var matchedFilm:WatchFilm? {USBFilmMetadata.film(for:self)}
 var mediaURL: URL? { USBMovieLibrary.playableURL(url) }
 var isEpisode: Bool {
  let s = (name + " " + path).lowercased()
  return s.contains("第") && (s.contains("季") || s.contains("集"))
    || s.range(of: #"(?i)\bs\d{1,2}e\d{1,3}\b"#,options:.regularExpression) != nil
    || s.range(of: #"(?i)\b(?:ep|episode)[. _-]?\d+\b"#,options:.regularExpression) != nil
    || s.range(of: #"\d{2,3}\s*[-–]\s*\d{2,3}"#,options:.regularExpression) != nil
 }
 var releaseYear: Int? {
  let s=URL(fileURLWithPath:name).deletingPathExtension().lastPathComponent
  guard let range=s.range(of:#"(?<!\d)(?:19|20)\d{2}(?!\d)"#,options:.regularExpression) else{return nil}
  return Int(s[range])
 }
 var displayTitle: String {
  if let film=matchedFilm {return "\(film.title) (\(film.year))"}
  let base=URL(fileURLWithPath:name).deletingPathExtension().lastPathComponent
  // Common release suffixes must not show up as the film's public title.
  let clean=base.replacingOccurrences(of:"_",with:" ").replacingOccurrences(of:".",with:" ")
  let pattern=#"(?i)[\s\[\(]+(?:19|20)\d{2}(?:[\s\]\)\.\-_].*)?$|[\s\[\(]+(?:2160p|1080p|720p|480p|bluray|bdrip|web-dl|remux|x264|x265|hevc|hdr|dv)(?:[\s\]\)\.\-_].*)?$"#
  let stem=clean.replacingOccurrences(of:pattern,with:"",options:.regularExpression)
  let result=stem.replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
  if let year=releaseYear,!isEpisode,!result.isEmpty {return String("\(result) (\(year))".prefix(100))}
  return String((result.isEmpty ? base : result).prefix(100))
 }
 var posterSearchTitle: String {
  let title=displayTitle
  if let year=releaseYear {return title.replacingOccurrences(of:" (\(year))",with:"")}
  if isEpisode {
   // Do not send episode numbers, file paths or release tags to a public artwork service.
   if let part=title.range(of:#"(?i)(?:s\d{1,2}e\d+|\d{2,3}\s*[-–]\s*\d{2,3}|第\s*\d+\s*集)"#,options:.regularExpression) {
    return String(title[..<part.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines)
   }
  }
  return title
 }
 var savedMedia: SavedMedia? {
  guard let mediaURL else {return nil}
  return SavedMedia(id:UUID(),title:displayTitle,url:mediaURL.absoluteString,favorite:false,lastPlayed:nil)
 }
}

@MainActor final class USBCatalogStore: ObservableObject {
 @Published private(set) var movies:[USBMovie]=[]
 @Published private(set) var loading=false
 @Published private(set) var error=""
 private var lastLoaded:Date?
 func refresh(force:Bool=false) async {
  if loading {return}
  if !force,let lastLoaded,Date().timeIntervalSince(lastLoaded)<90 {return}
  loading=true
  defer {loading=false}
  do {
   let fetched=try await USBMovieLibrary.list()
   movies=fetched.sorted {
    $0.displayTitle.localizedStandardCompare($1.displayTitle)==(.orderedAscending)
   }
   lastLoaded=Date()
   error=""
  } catch {
   self.error="无法读取 U 盘影视目录：\(error.localizedDescription)"
  }
 }
}

@MainActor final class USBPosterStore: ObservableObject {
 @Published private(set) var covers:[String:URL]=[:]
 private var inFlight=Set<String>()
 private var attempts:[String:Date]=[:]

 func cover(for movie:USBMovie) async {
  guard covers[movie.id]==nil,!inFlight.contains(movie.id) else{return}
  if let last=attempts[movie.id],Date().timeIntervalSince(last)<900 {return}
  inFlight.insert(movie.id)
  attempts[movie.id]=Date()
  defer {inFlight.remove(movie.id)}
  let title=movie.posterSearchTitle
  guard (3...80).contains(title.count),
   title.range(of:#"[A-Za-z\p{Han}]"#,options:.regularExpression) != nil else{return}
  let alias=movie.matchedFilm?.aliases.first ?? title
  let searches:[(String,String)]=movie.matchedFilm == nil
   ? [("CN",title),("US",title)]
   : [("CN",title),("HK",title),("US",alias),("KR",alias),("DK",alias)]
  for (country,term) in searches where !Task.isCancelled {
   var comps=URLComponents(string:"https://itunes.apple.com/search")
   comps?.queryItems=[
    URLQueryItem(name:"term",value:term),
    URLQueryItem(name:"entity",value:movie.isEpisode ? "tvSeason" : "movie"),
    URLQueryItem(name:"country",value:country),
    URLQueryItem(name:"limit",value:"20")
   ]
   guard let url=comps?.url else{continue}
   var request=URLRequest(url:url,cachePolicy:.returnCacheDataElseLoad,timeoutInterval:7)
   request.setValue("application/json",forHTTPHeaderField:"Accept")
   guard let (data,response)=try? await URLSession.shared.data(for:request),
    (response as? HTTPURLResponse)?.statusCode==200,
    data.count<=512_000,
    let index=try? JSONDecoder().decode(ITunesPosterResults.self,from:data) else{continue}
   if let row=index.results.first(where:{entry in
    USBArtworkMatch.accepts(movie:movie,title:entry.trackName ?? entry.collectionName ?? "",
     releaseDate:entry.releaseDate)
   }),let artwork=row.artworkUrl100,artwork.hasPrefix("https://"),
    let posterURL=URL(string:artwork),["https"].contains(posterURL.scheme?.lowercased() ?? "") {
    covers[movie.id]=posterURL
    return
   }
  }
 }
 private struct ITunesPosterResults:Decodable {
  let results:[Poster]
  struct Poster:Decodable {
   let trackName:String?
   let collectionName:String?
   let releaseDate:String?
   let artworkUrl100:String?
  }
 }
}

@MainActor struct USBPosterTile:View {
 let movie:USBMovie
 @ObservedObject var posters:USBPosterStore
 @ObservedObject var tmdb:TMDBCatalogStore
 var width:CGFloat=138
 var height:CGFloat=180
 var body:some View {
  ZStack {
   RoundedRectangle(cornerRadius:12).fill(
    LinearGradient(colors:movie.isEpisode ? [.indigo,.purple,.black] : [.blue,.teal,.black],
     startPoint:.topLeading,endPoint:.bottomTrailing))
   if let art=tmdb.cover(for:movie) ?? posters.covers[movie.id] {
    AsyncImage(url:art) {phase in
     if let image=phase.image {image.resizable().scaledToFill()}
     else {placeholder}
    }
   } else {placeholder}
  }
  .frame(width:width,height:height)
  .clipped().clipShape(RoundedRectangle(cornerRadius:12))
  .overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.12)))
  .task(id:movie.id+"-"+String(tmdb.generation)) {
   await tmdb.lookup(movie)
   if tmdb.cover(for:movie)==nil {await posters.cover(for:movie)}
  }
  .accessibilityLabel(tmdb.title(for:movie))
 }
 private var placeholder:some View {
  VStack(spacing:10) {
   Image(systemName:movie.isEpisode ? "play.tv" : "film.stack").font(.system(size:32)).foregroundStyle(.white.opacity(0.8))
   Text(tmdb.title(for:movie)).font(.caption.bold()).multilineTextAlignment(.center)
    .foregroundStyle(.white).lineLimit(4).padding(.horizontal,8)
  }.frame(maxWidth:.infinity,maxHeight:.infinity)
 }
}
