import Foundation

struct WatchFilm: Codable, Identifiable, Equatable {
 let id:String
 let title:String
 let year:Int
 let aliases:[String]
 let tags:[String]
 let synopsis:String
 var sourceURL:String? = nil
}
struct WatchRecord: Codable, Identifiable {
 let id:String
 var title:String
 var completedAt:Date
 var rating:Int?
 var tags:[String]
 var note:String
}
struct FilmSuggestion: Identifiable {
 let film:WatchFilm
 let reason:String
 let connection:String
 var id:String {film.id}
}
enum FilmTaste {
 static let tags=["悬疑","反转","低血腥","黑色幽默","喜剧","爱情","生活化","互怼","误会","轻松","温情","家庭","科幻","动画","韩国","现实题材","慢节奏","快节奏","心理","压抑","血腥"]
 static func clean(_ raw:String)->String {
  var s=raw.removingPercentEncoding ?? raw
  s=(s as NSString).lastPathComponent
  s=s.replacingOccurrences(of:#"\.(mkv|mp4|m4v|mov|avi|ts)$"#,with:"",options:.regularExpression)
  s=s.replacingOccurrences(of:#"(?i)[ ._\-\[]+(?:2160p|1080p|720p|bluray|bdrip|remux|webrip|web-dl|x265|x264|hevc|hdr|dv)\b.*$"#,with:"",options:.regularExpression)
  return s.replacingOccurrences(of:".",with:" ").replacingOccurrences(of:"_",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)
 }
 static func key(_ s:String)->String {s.lowercased().unicodeScalars.filter{CharacterSet.alphanumerics.contains($0)}.map(String.init).joined()}
 static func match(_ title:String,catalog:[WatchFilm])->WatchFilm? {
  let s=key(clean(title))
  let matches=catalog.filter{film in ([film.title]+film.aliases).contains{alias in let k=key(alias);return s==k || s==k+String(film.year) || (k.count>=4 && s.hasPrefix(k+String(film.year)))}}
  return matches.count==1 ? matches[0] : nil
 }
 static func suggestions(_ records:[WatchRecord],catalog:[WatchFilm],dismissed:Set<String>)->[FilmSuggestion] {
  guard !records.isEmpty else{return []}
  let seen=Set(records.map(\.id))
  var weights=[String:Double]()
  for r in records {
   let w=r.rating.map{Double($0-3)} ?? 0.25
   for t in Set(r.tags) {weights[t,default:0]+=w}
  }
  return catalog.filter{film in !seen.contains(film.id) && !dismissed.contains(film.id) && !records.contains{key(clean($0.title))==key(film.title)}}.map{film -> (Double,FilmSuggestion) in
   let shared=film.tags.filter{(weights[$0] ?? 0)>0}.sorted{(weights[$0] ?? 0)>(weights[$1] ?? 0)}
   let related=records.filter{($0.rating ?? 3)>=3 && !Set($0.tags).intersection(film.tags).isEmpty}.sorted{($0.rating ?? 3)>($1.rating ?? 3)}.prefix(2)
   let liked=related.filter{($0.rating ?? 0)>=4}
   let names=related.map{"《"+$0.title+"》"}.joined(separator:"、")
   let connection=shared.isEmpty ? "这是一部探索推荐，现有观影记录尚未提供明确的相似偏好。" : "与你记录中的"+shared.prefix(3).joined(separator:"、")+"有关"+(names.isEmpty ? "。" : "；参考了"+names+"。")
   let reason=liked.isEmpty ? "根据已看题材尝试推荐；看过只作为弱参考，评分后会继续调整。" : "你对"+liked.map{"《"+$0.title+"》"}.joined(separator:"、")+"给过较高评价，这部也包含"+shared.prefix(2).joined(separator:"、")+"元素。"
   return (film.tags.reduce(0){$0+(weights[$1] ?? 0)},FilmSuggestion(film:film,reason:reason,connection:connection))
  }.sorted{a,b in a.0==b.0 ? a.1.id<b.1.id : a.0>b.0}.prefix(6).map{$0.1}
 }
}
// Tracks only continuous playback. Scrubbing, buffering, repeats and reconnect
// gaps cannot manufacture coverage. This state is unrelated to source cleanup.
struct WatchCoverage {
 private var source=""
 private var previous:(Double,Double,Bool)?
 private var ranges:[ClosedRange<Double>]=[]
 mutating func sample(source:String,position:Double,duration:Double,playing:Bool,now:Double,storyEnd:Double?=nil)->Bool {
  guard !source.isEmpty,position.isFinite,duration.isFinite,duration>=60,position>=0 else {previous=nil;return false}
  if self.source != source {self.source=source;previous=nil;ranges=[]}
  defer {previous=(position,now,playing)}
  if let (last,time,wasPlaying)=previous {
   let dt=now-time,delta=position-last
   if wasPlaying && playing && dt>0 && dt<=5 && delta>0 && delta<=dt*3+2 {
    ranges.append(last...position)
    var merged=[ClosedRange<Double>]()
    for r in ranges.sorted(by:{$0.lowerBound<$1.lowerBound}) {
     if let p=merged.last,r.lowerBound<=p.upperBound+0.1 {merged[merged.count-1]=p.lowerBound...max(p.upperBound,r.upperBound)} else {merged.append(r)}
    }
    ranges=merged
   }
  }
  let end=(storyEnd.map{ $0>=60 && $0<=duration ? $0 : duration } ?? duration)
  let coverage=ranges.reduce(0){$0+max(0,min(end,$1.upperBound)-min(end,$1.lowerBound))}
  return coverage>=end*0.7 && position>=end-3 && position<=duration+3
 }
}
