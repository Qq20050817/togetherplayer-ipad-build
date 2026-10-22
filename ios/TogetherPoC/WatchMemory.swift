import Foundation
import Combine

@MainActor final class WatchMemory:ObservableObject {
 @Published private(set) var records:[WatchRecord]=[]
 @Published private(set) var dismissed=Set<String>()
 @Published private(set) var storageError=""
 @Published var automaticTitle=""
 private let defaults:UserDefaults
 private let onlineEnabled:Bool
 private let storageKey="watch-memory-v1"
 private struct Archive:Codable {var records:[WatchRecord];var dismissed:Set<String>}
 @Published private(set) var catalog:[WatchFilm]
 @Published private(set) var catalogStatus="内置片单可离线推荐"
 private var refreshing=false
 private var lastRefreshSignature=""
 private var lastRefreshAt:Date?
 init(defaults:UserDefaults = .standard,onlineEnabled:Bool=true) {
  self.onlineEnabled=onlineEnabled
  self.defaults=defaults
  if let url=Bundle.main.url(forResource:"film-catalog",withExtension:"json"),
     let data=try? Data(contentsOf:url),let films=try? JSONDecoder().decode([WatchFilm].self,from:data) {catalog=films} else {catalog=[]}
  if let data=defaults.data(forKey:"watch-catalog-cache-v1"),let cached=try? JSONDecoder().decode([WatchFilm].self,from:data) {catalog += cached.filter{f in !catalog.contains{$0.id==f.id}}}
  if let data=defaults.data(forKey:storageKey) {
   do {let archive=try JSONDecoder().decode(Archive.self,from:data);records=archive.records;dismissed=archive.dismissed}
   catch {storageError="观影档案读取失败，原始数据已保留。";return}
  }
 }
 func refreshCatalog() async {
  guard onlineEnabled,!refreshing,!records.isEmpty else{return}
  let genres:[String:String]=["喜剧":"4404","悬疑":"4416","爱情":"4412","科幻":"4413","动画":"4402","现实题材":"4406","家庭":"4410"]
  var weights=[String:Double]()
  for r in records {for t in r.tags {weights[t,default:0]+=r.rating.map{Double($0-3)} ?? 0.25}}
  let chosen=weights.filter{genres[$0.key] != nil && $0.value>0}.sorted{$0.value>$1.value}.prefix(2).compactMap{genres[$0.key]}
  let targets=chosen.isEmpty ? ["4404","4416"] : chosen
  let signature=targets.sorted().joined(separator:",")
  if signature==lastRefreshSignature,let date=lastRefreshAt,Date().timeIntervalSince(date)<86400 {return}
  refreshing=true;catalogStatus="正在按观影偏好更新在线片单…"
  defer {refreshing=false}
  var discovered=[WatchFilm]()
  for genre in targets {
   guard let url=URL(string:"https://itunes.apple.com/hk/rss/topmovies/limit=50/genre=\(genre)/json") else {continue}
   do {
    var request=URLRequest(url:url);request.timeoutInterval=15
    let (data,response)=try await URLSession.shared.data(for:request)
    guard (response as? HTTPURLResponse)?.statusCode==200,
     let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],
     let feed=root["feed"] as? [String:Any],let entries=feed["entry"] as? [[String:Any]] else{continue}
    for entry in entries {
     func label(_ key:String)->String {(entry[key] as? [String:Any])?["label"] as? String ?? ""}
     guard let identifier=entry["id"] as? [String:Any],let attrs=identifier["attributes"] as? [String:Any],let id=attrs["im:id"] as? String else {continue}
     let title=label("im:name"),description=label("summary")
     let year=Int(label("im:releaseDate").prefix(4)) ?? 0
     let source=identifier["label"] as? String ?? ""
     guard !title.isEmpty,!description.isEmpty,year>1900,let link=URL(string:source),link.scheme=="https",link.host=="itunes.apple.com" else{continue}
     if FilmTaste.match(title+" "+String(year),catalog:catalog) != nil {continue}
     let tags=genres.filter{$0.value==genre}.map(\.key)
     discovered.append(WatchFilm(id:"apple:"+id,title:title,year:year,aliases:[],tags:tags,synopsis:String(description.prefix(220)),sourceURL:source))
    }
   } catch {continue}
  }
  if discovered.isEmpty {catalogStatus="在线片单暂不可用，继续使用已保存片单";return}
  for film in discovered {
   if let i=catalog.firstIndex(where:{$0.id==film.id}) {
    var merged=film;merged=WatchFilm(id:film.id,title:film.title,year:film.year,aliases:film.aliases,tags:Array(Set(catalog[i].tags+film.tags)).sorted(),synopsis:film.synopsis,sourceURL:film.sourceURL);catalog[i]=merged
   } else {catalog.append(film)}
  }
  let cached=Array(catalog.filter{$0.sourceURL != nil}.suffix(400))
  if let data=try? JSONEncoder().encode(cached) {defaults.set(data,forKey:"watch-catalog-cache-v1")}
  lastRefreshSignature=signature;lastRefreshAt=Date()
  catalogStatus="在线片单已更新 · 共 \(catalog.count) 部；联网时按偏好更新，离线沿用缓存"
 }
 var suggestions:[FilmSuggestion] {FilmTaste.suggestions(records,catalog:catalog,dismissed:dismissed)}
 func record(_ title:String) {
  let cleaned=FilmTaste.clean(title)
  guard storageError.isEmpty,!cleaned.isEmpty,!["一起看电影","本地影片","电影","movie","bunny"].contains(cleaned.lowercased()) else{return}
  let film=FilmTaste.match(title,catalog:catalog)
  let id=film?.id ?? "title:"+FilmTaste.key(cleaned)
  guard !records.contains(where:{$0.id==id}) else{return}
  records.insert(WatchRecord(id:id,title:film?.title ?? cleaned,completedAt:Date(),rating:nil,tags:film?.tags ?? [],note:""),at:0);save();Task {await refreshCatalog()}
 }
 func feedback(_ id:String,rating:Int?,tags:[String],note:String) {
  guard let i=records.firstIndex(where:{$0.id==id}) else{return}
  records[i].rating=rating;records[i].tags=tags;records[i].note=String(note.prefix(500));save();Task {await refreshCatalog()}
 }
 func forget(_ id:String) {records.removeAll{$0.id==id};save()}
 func dismiss(_ id:String) {dismissed.insert(id);save()}
 func restoreSuggestions() {dismissed=[];save()}
 private func save() {
  guard storageError.isEmpty else{return}
  do {defaults.set(try JSONEncoder().encode(Archive(records:records,dismissed:dismissed)),forKey:storageKey)}
  catch {storageError="观影档案保存失败，请保留当前页面。"}
 }
}
