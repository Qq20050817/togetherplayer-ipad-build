import Foundation

// Names are a suggestion only. A transcode changes bytes and cannot pass exact
// file matching. User confirmation and a duration check remain mandatory.
enum MovieVariantPolicy {
 enum DurationCheck: Equatable {case waiting, compatible, different}
 static func duration(localMs: Double,offsetMs: Double,roomMs: Double) -> DurationCheck {
  guard localMs.isFinite,offsetMs.isFinite,roomMs.isFinite,localMs>0,roomMs>0,localMs-offsetMs>0 else {return .waiting}
  return abs(localMs-offsetMs-roomMs)<=5000 ? .compatible : .different
 }
 static func normalizedName(_ name: String) -> String {
  var value=name.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
  let quality="(?:流畅|标清|高清|超清|原画|蓝光|360p|480p|540p|720p|1080p|1440p|2160p|4k|sd|hd|fhd|uhd)"
  let separators="[\\s._\\-\\[\\]【】()（）]"
  for _ in 0..<8 {
   let previous=value
   value=value.replacingOccurrences(of:"\\.(?:mp4|mkv|mov|m4v|avi|ts|webm)$",with:"",options:.regularExpression)
   value=value.replacingOccurrences(of:"^"+separators+"*"+quality+separators+"+",with:"",options:.regularExpression)
   value=value.replacingOccurrences(of:separators+"+"+quality+separators+"*$",with:"",options:.regularExpression)
   if value==previous {break}
  }
  return value.replacingOccurrences(of:separators+"+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
 }
 static func namesSuggestSameMovie(_ first: String,_ second: String) -> Bool {
  let first=normalizedName(first),second=normalizedName(second)
  return !first.isEmpty && first==second
 }
}

struct LocalQualityCandidate {
 let url: URL
 let roomID: String
 let mediaURL: String
 let roomTitle: String
}

enum PlaybackTime {
 static func clock(_ seconds: Double) -> String {
  guard seconds.isFinite,seconds>=0 else {return "00:00"}
  let value=Int(min(seconds,864000))
  return value>=3600 ? String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60) : String(format:"%02d:%02d",value/60,value%60)
 }
 static func remaining(duration: Double,position: Double) -> String {
  guard duration.isFinite,duration>0,position.isFinite else {return "剩余 --:--"}
  return "剩余 "+clock(ceil(max(0,duration-max(0,position))))
 }
}
