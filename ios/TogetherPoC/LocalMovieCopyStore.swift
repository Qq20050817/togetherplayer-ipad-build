import Foundation
import CryptoKit

/// Only this App's ImportedMovies tree is managed. Provider originals are never removed.
enum LocalMovieCopyStore {
 struct ImportResult {let url:URL;let reused:Bool}
 struct Entry:Identifiable {
  var id:String {url.standardizedFileURL.resolvingSymlinksInPath().path}
  let url:URL
  let stamp:CleanupFileStamp
 }
 enum Failure:LocalizedError {
  case invalidURL,unreadable,changed,protectedFile,unsafeLocation
  var errorDescription:String? {
   switch self {
   case .invalidURL:return "请选择已下载的本地电影文件。"
   case .unreadable:return "导入的电影副本暂时不可读取，请检查本机存储空间。"
   case .changed:return "文件在核对时发生变化，请重新选择。"
   case .protectedFile:return "正在使用的影片已保留，请先切换影片再删除。"
   case .unsafeLocation:return "只能管理 App 内的导入副本，原文件已保留。"
   }
  }
 }
 // Import, duplicate inspection and deletion share one off-main file-operation gate.
 private static let gate=NSLock()
 static var documents:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]}
 private static func inside(_ file:URL,_ directory:URL)->Bool {
  let folder=directory.standardizedFileURL.resolvingSymlinksInPath().path
  return file.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(folder+"/")
 }
 private static func root(_ documents:URL)->URL {documents.appendingPathComponent("ImportedMovies",isDirectory:true)}
 private static func entriesUnlocked(_ documents:URL)throws->[Entry] {
  let fm=FileManager.default,folder=root(documents)
  guard fm.fileExists(atPath:folder.path) else{return []}
  // No recursive traversal: legacy imports use one UUID folder per movie.
  guard try folder.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else{throw Failure.unsafeLocation}
  var result=[Entry]()
  for directory in try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) {
   guard UUID(uuidString:directory.lastPathComponent) != nil,
         (try? directory.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey])).map({$0.isDirectory==true && $0.isSymbolicLink != true})==true else{continue}
   for url in try fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) {
    guard inside(url,folder),let stamp=try? CleanupFileStamp.read(url) else{continue}
    result.append(Entry(url:url,stamp:stamp))
   }
  }
  return result.sorted{$0.stamp.modified==$1.stamp.modified ? $0.id<$1.id : $0.stamp.modified<$1.stamp.modified}
 }
 static func entries(documents:URL=LocalMovieCopyStore.documents)throws->[Entry] {
  gate.lock();defer{gate.unlock()};return try entriesUnlocked(documents)
 }
 private static func digest(_ url:URL,stamp:CleanupFileStamp,progress:(Int)->Void)throws->String {
  let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
  var hash=SHA256(),bytes:Int64=0,last = -1
  while true {
   try Task.checkCancellation()
   let count=try autoreleasepool {()throws->Int in
    let block=try handle.read(upToCount:1_048_576) ?? Data()
    if !block.isEmpty {hash.update(data:block)}
    return block.count
   }
   if count==0 {break};bytes+=Int64(count)
   let percent=Int(Double(bytes)*100/Double(max(1,stamp.size)))
   if percent != last {last=percent;progress(min(100,percent))}
  }
  guard bytes==stamp.size,try CleanupFileStamp.read(url)==stamp else{throw Failure.changed}
  return hash.finalize().map{String(format:"%02x",$0)}.joined()
 }
 static func persist(_ selected:URL,documents:URL=LocalMovieCopyStore.documents)throws->URL {
  try persistResult(selected,documents:documents).url
 }
 static func persistResult(_ selected:URL,documents:URL=LocalMovieCopyStore.documents,progress:(String)->Void={_ in})throws->ImportResult {
  gate.lock();defer{gate.unlock()}
  try Task.checkCancellation()
  guard selected.isFileURL,!selected.lastPathComponent.isEmpty else{throw Failure.invalidURL}
  let fm=FileManager.default
  let stamp=try CleanupFileStamp.read(selected)
  guard fm.isReadableFile(atPath:selected.path) else{throw Failure.unreadable}
  let inbox=documents.appendingPathComponent("Inbox",isDirectory:true)
  if inside(selected,documents) && !inside(selected,inbox) {return ImportResult(url:selected,reused:true)}
  let candidates=try entriesUnlocked(documents).filter{$0.stamp.size==stamp.size}
  if !candidates.isEmpty {
   let key=try digest(selected,stamp:stamp){progress("正在核对重复影片 \($0)%…")}
   for (index,entry) in candidates.enumerated() {
    let existing=try digest(entry.url,stamp:entry.stamp){progress("正在核对已有副本 \(index+1)/\(candidates.count) · \($0)%…")}
    if key==existing {
     guard try CleanupFileStamp.read(selected)==stamp,try CleanupFileStamp.read(entry.url)==entry.stamp else{throw Failure.changed}
     // Discard only the newly supplied Inbox copy owned by this App.
     if inside(selected,inbox) {try fm.removeItem(at:selected)}
     return ImportResult(url:entry.url,reused:true)
    }
   }
  }
  try Task.checkCancellation()
  let folder=root(documents).appendingPathComponent(UUID().uuidString,isDirectory:true)
  try fm.createDirectory(at:folder,withIntermediateDirectories:true)
  let target=folder.appendingPathComponent(selected.lastPathComponent)
  do {
   progress("正在保存影片副本…")
   // Relocate only an App-container copy; never move a provider original.
   if inside(selected,documents.deletingLastPathComponent()) {try fm.moveItem(at:selected,to:target)}
   else {try fm.copyItem(at:selected,to:target)}
   guard fm.isReadableFile(atPath:target.path),try CleanupFileStamp.read(target).size==stamp.size else{throw Failure.unreadable}
   return ImportResult(url:target,reused:false)
  } catch {try? fm.removeItem(at:folder);throw error}
 }
 /// Full SHA256 of each same-size candidate. Names and sample fingerprints never authorize deletion.
 /// Returns extras only; keep the current file or oldest copy in every exact-content group.
 static func duplicateExtras(documents:URL=LocalMovieCopyStore.documents,protected:Set<String>=[],progress:(String)->Void={_ in})throws->[Entry] {
  gate.lock();defer{gate.unlock()}
  let all=try entriesUnlocked(documents)
  let groups=Dictionary(grouping:all,by:{$0.stamp.size}).values.filter{$0.count>1}
  var extras=[Entry](),done=0
  let total=groups.reduce(0){$0+$1.count}
  for group in groups {
   var hashes=[String:[Entry]]()
   for entry in group {
    try Task.checkCancellation()
    let key=try digest(entry.url,stamp:entry.stamp){progress("正在检查副本 \(done+1)/\(total) · \($0)%…")}
    hashes[key,default:[]].append(entry);done+=1
   }
   for identical in hashes.values where identical.count>1 {
    let keeper=identical.first(where:{protected.contains($0.id)}) ?? identical[0]
    extras+=identical.filter{$0.id != keeper.id && !protected.contains($0.id)}
   }
  }
  return extras
 }
 static func remove(_ entry:Entry,documents:URL=LocalMovieCopyStore.documents,protected:Set<String>=[])throws {
  gate.lock();defer{gate.unlock()}
  guard !protected.contains(entry.id) else{throw Failure.protectedFile}
  let folder=root(documents)
  guard inside(entry.url,folder),entry.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL==folder.standardizedFileURL,
        UUID(uuidString:entry.url.deletingLastPathComponent().lastPathComponent) != nil,
        try entriesUnlocked(documents).contains(where:{$0.id==entry.id && $0.stamp==entry.stamp}) else{throw Failure.unsafeLocation}
  let result=WatchedFileCleanup.remove([CleanupFile(url:entry.url,stamp:entry.stamp,isMovie:true)],in:entry.url.deletingLastPathComponent())
  guard result.failed.isEmpty,result.deleted.count==1 else{throw Failure.changed}
  // Remove an empty import directory only; associated files are kept.
  let directory=entry.url.deletingLastPathComponent()
  if (try? FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)==true {try? FileManager.default.removeItem(at:directory)}
 }
}
