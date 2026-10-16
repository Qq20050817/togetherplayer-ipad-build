import Foundation

struct RoomMovieContext:Codable,Equatable {
 let server:String
 let roomID:String
 let mediaID:String
 init(server:String,roomID:String,mediaID:String) {
  self.server=server.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
  self.roomID=roomID;self.mediaID=mediaID
 }
}
struct RoomMovieSelection:Codable {
 let version:Int
 let context:RoomMovieContext
 let name:String
 let relativePath:String?
 let bookmark:Data?
 let size:Int64
 let modified:Date
 let confirmedVariant:Bool
 let referenceDuration:Double
 enum Failure:LocalizedError {
  case invalid,changed,unavailable,mismatch
  var errorDescription:String? {
   switch self {
   case .invalid:return "保存的本机影片记录无效，请重新选择一次。"
   case .changed:return "记住的影片已被替换或修改，请重新选择核对。"
   case .unavailable:return "记住的影片暂时不可读取，请确认文件仍在本机，或重新选择授权。"
   case .mismatch:return "记住的本机文件与房间当前影片不匹配，请重新选择。"
   }
  }
 }
 final class Resolved {
  let url:URL
  let refreshed:RoomMovieSelection
  private var scoped:Bool
  init(url:URL,scoped:Bool,refreshed:RoomMovieSelection){self.url=url;self.scoped=scoped;self.refreshed=refreshed}
  // Called once on the main actor after context/generation checks. The player
  // then owns this grant until releaseLocalFileAccess, including backgrounding.
  func transferAccess()->Bool {let result=scoped;scoped=false;return result}
  deinit {if scoped {url.stopAccessingSecurityScopedResource()}}
 }
 private static func relative(_ file:URL,documents:URL)->String? {
  let folder=documents.standardizedFileURL.resolvingSymlinksInPath().path+"/"
  let path=file.standardizedFileURL.resolvingSymlinksInPath().path
  return path.hasPrefix(folder) ? String(path.dropFirst(folder.count)) : nil
 }
 static func capture(_ url:URL,context:RoomMovieContext,documents:URL,confirmedVariant:Bool,referenceDuration:Double)throws->Self {
  try Task.checkCancellation()
  guard url.isFileURL,!context.roomID.isEmpty,!context.mediaID.isEmpty else{throw Failure.invalid}
  let scoped=url.startAccessingSecurityScopedResource();defer{if scoped {url.stopAccessingSecurityScopedResource()}}
  let stamp=try CleanupFileStamp.read(url)
  guard FileManager.default.isReadableFile(atPath:url.path) else{throw Failure.unavailable}
  let path=relative(url,documents:documents)
  // Documents-relative locations survive container changes after signing or
  // update. External files use iOS's persistent document-picker bookmark grant.
  let data=path==nil ? try url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil) : nil
  return Self(version:1,context:context,name:url.lastPathComponent,relativePath:path,bookmark:data,size:stamp.size,modified:stamp.modified,confirmedVariant:confirmedVariant,referenceDuration:referenceDuration.isFinite ? max(0,referenceDuration) : 0)
 }
 func resolve(documents:URL)throws->Resolved {
  try Task.checkCancellation()
  guard version==1,size>=0,!context.roomID.isEmpty,!context.mediaID.isEmpty else{throw Failure.invalid}
  let url:URL
  if let path=relativePath {
   guard bookmark==nil,!path.isEmpty,!path.hasPrefix("/"),!path.split(separator:"/").contains("..") else{throw Failure.invalid}
   url=documents.appendingPathComponent(path).standardizedFileURL
   guard Self.relative(url,documents:documents)==path else{throw Failure.invalid}
  } else if let data=bookmark {
   var stale=false
   url=try URL(resolvingBookmarkData:data,options:.withoutUI,relativeTo:nil,bookmarkDataIsStale:&stale)
  } else {throw Failure.invalid}
  guard url.isFileURL else{throw Failure.invalid}
  let scoped=url.startAccessingSecurityScopedResource()
  do {
   let stamp=try CleanupFileStamp.read(url)
   guard FileManager.default.isReadableFile(atPath:url.path) else{throw Failure.unavailable}
   guard stamp.size==size,stamp.modified==modified else{throw Failure.changed}
   if let ref=BaiduMediaReference(value:context.mediaID),!confirmedVariant {
    let identity=try BaiduFileIdentity.localFile(url)
    guard ref.matches(fingerprint:identity.fingerprint,size:identity.size) else{throw Failure.mismatch}
   }
   try Task.checkCancellation()
   let updated=try Self.capture(url,context:context,documents:documents,confirmedVariant:confirmedVariant,referenceDuration:referenceDuration)
   return Resolved(url:url,scoped:scoped,refreshed:updated)
  } catch {if scoped {url.stopAccessingSecurityScopedResource()};throw error}
 }
}

/// One active room association, local to this device. Never contains room tokens
/// or copies movie bytes. Client calls bounded metadata writes on the main actor;
/// bookmark/stat/sample verification run on a utility worker.
final class RoomMovieSelectionStore {
 let directory:URL
 let documents:URL
 private var file:URL {directory.appendingPathComponent("selection-v1.json")}
 init(directory:URL?=nil,documents:URL=LocalMovieCopyStore.documents) {
  self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RoomMovieSelection")
  self.documents=documents
 }
 static func applicationDefault()->RoomMovieSelectionStore {
  #if DEBUG
  let env=ProcessInfo.processInfo.environment
  if env["TOGETHER_PERSISTENCE_UI_TEST"]=="1" {
   let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RoomMovieSelectionUITest")
   return RoomMovieSelectionStore(directory:root)
  }
  if env["TOGETHER_UI_TEST"]=="1" || NSClassFromString("XCTestCase") != nil {
   return RoomMovieSelectionStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent("RoomMovieUnit-"+UUID().uuidString))
  }
  #endif
  return RoomMovieSelectionStore()
 }
 func load()throws->RoomMovieSelection? {
  guard FileManager.default.fileExists(atPath:file.path) else{return nil}
  let handle=try FileHandle(forReadingFrom:file);defer{try? handle.close()}
  let data=try handle.read(upToCount:65_537) ?? Data()
  guard !data.isEmpty,data.count<=65_536 else{throw RoomMovieSelection.Failure.invalid}
  let record=try JSONDecoder().decode(RoomMovieSelection.self,from:data)
  guard record.version==1 else{throw RoomMovieSelection.Failure.invalid}
  return record
 }
 func save(_ selection:RoomMovieSelection)throws {
  let data=try JSONEncoder().encode(selection)
  guard data.count<=65_536 else{throw RoomMovieSelection.Failure.invalid}
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  try data.write(to:file,options:.atomic)
 }
 func clear()throws {
  if FileManager.default.fileExists(atPath:file.path) {try FileManager.default.removeItem(at:file)}
 }
}
