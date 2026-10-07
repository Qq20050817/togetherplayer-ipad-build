import Foundation

// URL preparation stays on each viewer's device. Credentials in a local-only
// URL must never be copied into room metadata, chat or telemetry.
struct HlsSource: MediaSourceAdapter {
 func resolve(_ raw: String) -> URL? {HTTPSource().resolve(raw)}
}
struct WebDAVSource: MediaSourceAdapter {
 func resolve(_ raw: String) -> URL? {
  let value=raw.replacingOccurrences(of:"webdavs://",with:"https://").replacingOccurrences(of:"webdav://",with:"http://")
  return HTTPSource().resolve(value)
 }
}
struct MediaSourceCatalog {
 static func resolve(_ raw: String) -> URL? {WebDAVSource().resolve(raw.trimmingCharacters(in:.whitespacesAndNewlines))}
 static func canShare(_ raw: String) -> Bool {
  guard let u=resolve(raw),u.user==nil,u.password==nil,let parts=URLComponents(url:u,resolvingAgainstBaseURL:false) else {return false}
  let forbidden:Set<String>=["access_token","refresh_token","cookie","password"]
  return !(parts.queryItems ?? []).contains {forbidden.contains($0.name.lowercased())}
 }
}
