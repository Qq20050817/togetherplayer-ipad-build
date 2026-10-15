import Foundation

/// A UIDocumentPicker "asCopy" URL may live in a temporary Inbox. Relocate
/// that already-imported copy into app Documents before the picker is dismissed,
/// so the player, subtitle scanner and independent FFmpeg decoder share a
/// durable file URL for the entire session.
enum LocalMovieCopyStore {
 enum Failure: LocalizedError {
  case invalidURL, unreadable
  var errorDescription: String? {
   switch self {
   case .invalidURL: return "请选择已下载的本地电影文件。"
   case .unreadable: return "导入的电影副本暂时不可读取，请检查本机存储空间。"
   }
  }
 }
 private static func isInside(_ file: URL, directory: URL) -> Bool {
  let folder=directory.standardizedFileURL.resolvingSymlinksInPath().path
  let path=file.standardizedFileURL.resolvingSymlinksInPath().path
  return path.hasPrefix(folder.hasSuffix("/") ? folder : folder+"/")
 }
 static func persist(_ selected: URL, documents: URL = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]) throws -> URL {
  guard selected.isFileURL,!selected.lastPathComponent.isEmpty else {throw Failure.invalidURL}
  let fm=FileManager.default
  var isDirectory: ObjCBool=false
  guard fm.fileExists(atPath:selected.path,isDirectory:&isDirectory),!isDirectory.boolValue,
        fm.isReadableFile(atPath:selected.path) else {throw Failure.unreadable}
  let inbox=documents.appendingPathComponent("Inbox",isDirectory:true)
  // A provider may already have copied directly into persistent Documents.
  // In that case leave the user-visible file untouched.
  if isInside(selected, directory:documents) && !isInside(selected,directory:inbox) {return selected}
  let folder=documents.appendingPathComponent("ImportedMovies",isDirectory:true)
   .appendingPathComponent(UUID().uuidString,isDirectory:true)
  try fm.createDirectory(at:folder,withIntermediateDirectories:true)
  let target=folder.appendingPathComponent(selected.lastPathComponent,isDirectory:false)
  do {
   // Only move a copy already inside our own container. Never move an
   // external provider's original file, even if it was picked asCopy.
   if isInside(selected,directory:documents.deletingLastPathComponent()) {
    try fm.moveItem(at:selected,to:target)
   } else {
    try fm.copyItem(at:selected,to:target)
   }
   guard fm.isReadableFile(atPath:target.path) else {throw Failure.unreadable}
   return target
  } catch {
   try? fm.removeItem(at:folder)
   throw error
  }
 }
}
