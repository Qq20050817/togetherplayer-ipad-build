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
 var appCopyFiles:[CleanupFile]=[]
 var allFiles:[CleanupFile] {files+appCopyFiles}
 var bytes:Int64 {allFiles.reduce(0){$0+$1.stamp.size}}
}
enum CleanupFailure:LocalizedError {
 case unsafeFile,wrongFolder,tooManyFiles,changedFile,nonLocalLocation,unverifiedDeletion,copyMismatch
 var errorDescription:String? {
  switch self {
  case .unverifiedDeletion:return "删除后文件仍存在，未计为已删除。"
  case .copyMismatch:return "所选文件与 App 导入副本内容不同，未加入清理清单。"
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
 // Matching an imported copy requires an explicit original-folder grant and
 // byte-for-byte comparison. A same name/size or a sampled fingerprint is insufficient.
 static func planOriginalAndCopy(source:URL,folder:URL,importedSubtitle:URL?=nil)throws->CleanupPlan {
  guard isAppOwned(source) else{throw CleanupFailure.unsafeFile}
  try requireLocalLocation(folder)
  let copyPlan=try plan(source:source,folder:source.deletingLastPathComponent(),importedSubtitle:importedSubtitle)
  let original=folder.appendingPathComponent(source.lastPathComponent)
  let originalPlan=try plan(source:original,folder:folder)
  let before=try CleanupFileStamp.read(original)
  if before==copyPlan.files.first(where:{$0.isMovie})?.stamp {return originalPlan}
  let a=try FileHandle(forReadingFrom:source),b=try FileHandle(forReadingFrom:original)
  defer{try? a.close();try? b.close()}
  guard before.size==copyPlan.files.first(where:{$0.isMovie})?.stamp.size else{throw CleanupFailure.copyMismatch}
  while true {
   try Task.checkCancellation()
   let left=try a.read(upToCount:1_048_576) ?? Data()
   let right=try b.read(upToCount:1_048_576) ?? Data()
   guard left==right else{throw CleanupFailure.copyMismatch}
   if left.isEmpty {break}
  }
  guard try CleanupFileStamp.read(original)==before,
        try CleanupFileStamp.read(source)==copyPlan.files.first(where:{$0.isMovie})?.stamp else{throw CleanupFailure.changedFile}
  var result=originalPlan;result.appCopyFiles=copyPlan.files
  return result
 }
 static func verifyAbsent(_ url:URL)throws {
  do {_ = try FileManager.default.attributesOfItem(atPath:url.path)}
  catch {
   let e=error as NSError
   if e.domain==NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(e.code) {return}
   if e.domain==NSPOSIXErrorDomain && e.code==2 {return}
   throw error // Permission failures are not evidence that a file is gone.
  }
  throw CleanupFailure.unverifiedDeletion
 }
 static func remove(_ files:[CleanupFile],from plan:CleanupPlan)->(deleted:[String],failed:[String]) {
  let allowed=Dictionary(uniqueKeysWithValues:plan.allFiles.map{($0.id,$0.stamp)})
  let valid=files.filter{allowed[$0.id]==$0.stamp}
  let originals=valid.filter{file in plan.files.contains{$0.id==file.id}}
  let copies=valid.filter{file in plan.appCopyFiles.contains{$0.id==file.id}}
  let a=remove(originals,in:plan.folder)
  let b=remove(copies,in:plan.appCopyFiles.first?.url.deletingLastPathComponent() ?? plan.folder)
  return (a.deleted+b.deleted,a.failed+b.failed+files.filter{allowed[$0.id] != $0.stamp}.map{$0.name+"：不属于已确认清单"})
 }
 // Caller retains the folder scope until all I/O and post-delete checks finish.
 static func remove(_ files:[CleanupFile],in folder:URL,performRemoval:(URL)throws->Void={try FileManager.default.removeItem(at:$0)})->(deleted:[String],failed:[String]) {
  var deleted=[String](),failed=[String]()
  for file in files {
   guard file.url.deletingLastPathComponent().standardizedFileURL.path==folder.standardizedFileURL.path else{failed.append(file.name+"：目录不匹配");continue}
   var coordinationError:NSError?
   var failure:Error?
   var performed=false
   NSFileCoordinator().coordinate(writingItemAt:file.url,options:.forDeleting,error:&coordinationError) {coordinated in
    do {
     guard coordinated.standardizedFileURL.path==file.url.standardizedFileURL.path,try CleanupFileStamp.read(coordinated)==file.stamp else{throw CleanupFailure.changedFile}
     try performRemoval(coordinated)
     try verifyAbsent(coordinated)
     performed=true
    } catch {failure=error}
   }
   if let error=failure ?? coordinationError {failed.append(file.name+"："+error.localizedDescription)}
   else if !performed {failed.append(file.name+"：系统未执行删除，文件已保留")}
   else {deleted.append(file.name)}
  }
  return (deleted,failed)
 }
}
