import Foundation

// UI-only title inference. Never changes movie IDs, room synchronization or
// signed source URLs. A user can still override the suggested name manually.
enum FilmSourceTitle {
 static let mediaExtensions:Set<String> = [
  "mkv","mp4","m4v","mov","avi","webm","ts","m2ts","mpg","mpeg","wmv","flv"
 ]
 static func fromFileName(_ name:String)->String? {
  let file=name.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !file.isEmpty else{return nil}
  let url=URL(fileURLWithPath:file)
  let base=mediaExtensions.contains(url.pathExtension.lowercased()) ?
   url.deletingPathExtension().lastPathComponent : url.lastPathComponent
  let result=base.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !result.isEmpty else{return nil}
  return String(result.prefix(160))
 }
 static func fromMediaURL(_ raw:String)->String? {
  guard let url=MediaSourceCatalog.resolve(raw),
        mediaExtensions.contains(url.pathExtension.lowercased()) else{return nil}
  // The signed URL's query (expires, sig, etc.) is never a display title.
  return fromFileName(url.lastPathComponent)
 }
}
