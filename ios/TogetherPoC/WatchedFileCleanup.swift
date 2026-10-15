import Foundation

struct CleanupFileStamp:Equatable {
 let device:UInt64
 let inode:UInt64
 let size:Int64
 let modified:Date
 static func read(_ url:URL)throws->Self {
  let a=try FileManager.default.attributesOfItem(atPath:url.path)
  guard a[.type] as? FileAttributeType == .typeRegular,
        let device=a[.systemNumber] as? NSNumber,let inode=a[.systemFileNumber] as? NSNumber,
        let size=a[.size] as? NSNumber,let modified=a[.modificationDate] as? Date else {throw CleanupFailure.unsafeFile}
  return Self(device:device.uint64Value,inode:inode.uint64Value,size:size.int64Value,modified:modified)
 }
}
struct CleanupFile:Identifiable {
 var id:String {url.path}
 let url:URL
 let stamp:CleanupFileStamp
 let isMovie:Bool
 var name:String {url.lastPathComponent}
}
struct CleanupPlan {
 let source:URL
 let folder:URL
 let files:[CleanupFile]
 var bytes:Int64 {files.reduce(0){$0+$1.stamp.size}}
}
enum CleanupFailure:LocalizedError {
 case unsafeFile,wrongFolder,tooManyFiles,changedFile,nonLocalLocation
 var errorDescription:String? {
  switch self {
  case .unsafeFile:return "只支持清理本地普通文件，不能删除文件夹或替身。"
  case .wrongFolder:return "这个文件夹中没有当前正在观看的影片，请选择影片所在文件夹。"
  case .tooManyFiles:return "此文件夹文件过多，请选择更具体的影片文件夹。"
  case .nonLocalLocation:return "这里只清理设备本地文件；iCloud 或其他文件提供器请在“文件”App 中管理。"
  case .changedFile:return "文件已发生变化，未删除。请重新检查清理清单。"
  }
 }
}
enum WatchedFileCleanup {
 static func isAppOwned(_ source:URL)->Bool {
  let root=URL(fileURLWithPath:NSHomeDirectory()).resolvingSymlinksInPath().path+"/"
  return source.isFileURL && source.resolvingSymlinksInPath().path.hasPrefix(root)
 }
 static func requireLocalLocation(_ url:URL)throws {
  guard url.isFileURL else{throw CleanupFailure.unsafeFile}
  if (try? url.resourceValues(forKeys:[.isUbiquitousItemKey]).isUbiquitousItem)==true {throw CleanupFailure.nonLocalLocation}
  if isAppOwned(url){return}
  let path=url.resolvingSymlinksInPath().path
  // Only positively identify native device containers. File-provider materialized
  // copies can synchronize deletion back to a cloud account, so decline them.
  let localContainer=path.hasPrefix("/private/var/mobile/Containers/Data/Application/") || path.hasPrefix("/var/mobile/Containers/Data/Application/")
  guard localContainer,!path.contains("/File Provider Storage/"),!path.contains("/Mobile Documents/") else{throw CleanupFailure.nonLocalLocation}
 }
 static let subtitleExtensions:Set<String>=["srt","vtt","ass","ssa","sup","sub","idx","smi","ttml","dfxp"]
 private static let tags:Set<String>=["zh","zh-cn","zh-tw","zh-hk","zh-hans","zh-hant","chs","cht","chi","zho","cn","hans","hant","简体","繁体","简体中文","繁体中文","中文","中英","双语","eng","en","english","ja","jpn","jp","ko","kor","fr","fra","fre","de","deu","ger","es","spa","pt","por","ru","rus","it","ita","ar","ara","th","tha","vi","vie","id","ind","forced","sdh","cc","default","full","utf8","utf-8"]
 static func associatedSubtitle(_ name:String,movie:String)->Bool {
  let u=URL(fileURLWithPath:name),m=URL(fileURLWithPath:movie)
  guard subtitleExtensions.contains(u.pathExtension.lowercased()) else{return false}
  let base=m.deletingPathExtension().lastPathComponent.lowercased()
  let stem=u.deletingPathExtension().lastPathComponent.lowercased()
  if stem==base {return true}
  guard stem.hasPrefix(base+".") else{return false}
  let suffix=String(stem.dropFirst(base.count+1))
  let parts=suffix.split(whereSeparator:{".&+ _".contains($0)}).map(String.init)
  return !parts.isEmpty && parts.allSatisfy{tags.contains($0)}
 }
 static func plan(source:URL,folder:URL,importedSubtitle:URL?=nil)throws->CleanupPlan {
  try requireLocalLocation(source);try requireLocalLocation(folder)
  let folder=folder.standardizedFileURL
  let sourceStamp=try CleanupFileStamp.read(source)
  let children=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])
  guard children.count<=2000 else{throw CleanupFailure.tooManyFiles}
  // Match the original file identity, never just its display name.
  guard let movie=children.first(where:{
   guard $0.lastPathComponent==source.lastPathComponent,let stamp=try? CleanupFileStamp.read($0) else{return false}
   return stamp==sourceStamp
  }) else{throw CleanupFailure.wrongFolder}
  let importedStamp=importedSubtitle.flatMap{try? CleanupFileStamp.read($0)}
  var files=[CleanupFile(url:movie,stamp:sourceStamp,isMovie:true)]
  for url in children where url != movie && subtitleExtensions.contains(url.pathExtension.lowercased()) {
   guard let stamp=try? CleanupFileStamp.read(url) else{continue}
   let explicitlyImported=importedSubtitle?.lastPathComponent==url.lastPathComponent && importedStamp==stamp
   if explicitlyImported || associatedSubtitle(url.lastPathComponent,movie:movie.lastPathComponent) {
    files.append(CleanupFile(url:url,stamp:stamp,isMovie:false))
   }
  }
  return CleanupPlan(source:source,folder:folder,files:files.sorted{a,b in a.isMovie != b.isMovie ? a.isMovie : a.name.localizedStandardCompare(b.name) == .orderedAscending})
 }
 // Caller owns the folder security scope and detaches only its local player first.
 // Check identity again inside file coordination so reviewed paths cannot delete replacements.
 static func remove(_ files:[CleanupFile],in folder:URL)->(deleted:[String],failed:[String]) {
  var deleted=[String](),failed=[String]()
  for file in files {
   guard file.url.deletingLastPathComponent().standardizedFileURL.path==folder.standardizedFileURL.path else{failed.append(file.name+"：目录不匹配");continue}
   var coordinationError:NSError?
   var failure:Error?
   NSFileCoordinator().coordinate(writingItemAt:file.url,options:.forDeleting,error:&coordinationError) {coordinated in
    do {
     guard coordinated.standardizedFileURL.path==file.url.standardizedFileURL.path,try CleanupFileStamp.read(coordinated)==file.stamp else{throw CleanupFailure.changedFile}
     try FileManager.default.removeItem(at:coordinated)
    } catch {failure=error}
   }
   if let error=failure ?? coordinationError {failed.append(file.name+"："+error.localizedDescription)}
   else {deleted.append(file.name)}
  }
  return (deleted,failed)
 }
}
