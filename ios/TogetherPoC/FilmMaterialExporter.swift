import Foundation
import AVFoundation
import UIKit
import CryptoKit
import zlib

// Offline, explicitly initiated export. No film, frames or subtitles are
// automatically transmitted to a server or to an AI provider.
enum FilmMaterialExportFailure:LocalizedError {
 case localFileRequired,remoteUnavailable,missingSubtitles,framesUnavailable,missingDuration,tooManyFiles,sourceChanged,busy
 case frameExtractionDiagnostic(String)
 var errorDescription:String? {switch self {
  case .localFileRequired:return "请先选择本机影片，或可直接读取原始文件并支持 HTTP Range 的 U 盘影片链接。"
  case .remoteUnavailable:return "远程影片读取失败或未支持 HTTP Range；请确认 U 盘服务在线、原始片源链接有效，并重新选片。无需复制原片到 iPad。"
  case .missingSubtitles:return "未读取到完整字幕。可以先导入 SRT/ASS 字幕，再导出素材。"
  case .framesUnavailable:return "原片可读取字幕，但独立抽帧失败，未导出只有字幕的假完整素材。请确认本机文件可解码，或 U 盘 HTTP 片源支持随机读取。"
  case .frameExtractionDiagnostic(let detail):return "原片字幕已读取，但电影画面提取未达标（"+detail+"）。不会导出缺少画面的假完整素材；原片未改变。请将此诊断文字反馈以继续排查。"
  case .missingDuration:return "无法确定影片时长，请确认原片完整。"
  case .sourceChanged:return "提取期间原片发生变化，本次素材已取消，请重新提取。"
  case .tooManyFiles:return "素材包超过安全容量，已取消导出。"
  case .busy:return "上一项提取仍在释放资源，请稍后重试。"
 }}
}

struct FilmMaterialManifest:Codable {
 let schemaVersion:Int
 let title:String
 let durationMs:Int
 let sourceFingerprint:String
 let subtitleFingerprint:String
 let subtitleCueCount:Int
 let frameCount:Int
 let contactSheets:[String]
 let frameTimesMs:[Int]
 let frameExportMode:String
 var fingerprintAlgorithm="sha256-complete-file"
 let frameTimeline="frame-timeline.json"
 let requestedFrameCount:Int
 let missingFrameTimesMs:[Int]
}

enum FilmMaterialFingerprint {
 static func source(_ url:URL,progress:(Double)->Void={_ in})throws->String {
  if !url.isFileURL {return try remote(url,progress:progress)}
  let handle=try FileHandle(forReadingFrom:url)
  defer {try? handle.close()}
  let size=try handle.seekToEnd()
  guard size>0 else{throw FilmMaterialExportFailure.localFileRequired}
  try handle.seek(toOffset:0)
  // Full file SHA256, not the old first/last 64 KiB sample. Two files with
  // altered middle bytes must not silently share a strict-version bank.
  var sha=SHA256(),read:UInt64=0
  var reported = -1
  while true {
   let count=try autoreleasepool {() throws->Int in
    try Task.checkCancellation()
    let bytes=try handle.read(upToCount:1024*1024) ?? Data()
    sha.update(data:bytes);return bytes.count
   }
   if count==0 {break}
   read+=UInt64(count)
   let percent=Int(min(100,read*100/size))
   if percent != reported {reported=percent;progress(Double(percent)/100)}
  }
  guard read==size,try handle.seekToEnd()==size else{throw FilmMaterialExportFailure.localFileRequired}
  return sha.finalize().map{String(format:"%02x",$0)}.joined()

 }

 // Remote sources are sampled over three small HTTP requests, never copied to
 // iPad. This is a *different*, explicitly labelled identifier from the
 // complete-file SHA256 used for local films. Signed query tokens are excluded
 // so refreshing an expiring USB link does not invalidate an otherwise
 // unchanged film bank.
 static func remote(_ url:URL,session:URLSession = .shared,progress:(Double)->Void={_ in})throws->String {
  guard ["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil else {
   throw FilmMaterialExportFailure.localFileRequired
  }
  try Task.checkCancellation()
  func request(_ method:String,range:String?=nil)->URLRequest {
   var result=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:45)
   result.httpMethod=method
   if let range {result.setValue(range,forHTTPHeaderField:"Range")}
   return result
  }
  func load(_ request:URLRequest,expected:Int,limit:Int)->(Data,HTTPURLResponse)? {
   // URLSession range requests must stay bounded. A non-range server can
   // return the whole 50 GB movie; refuse it before receiving its body.
   let reader=FilmMaterialRangeRequest(limit:limit,expectedStatus:expected)
   return reader.fetch(request:request,configuration:session.configuration)
  }
  guard let (_,head)=load(request("HEAD"),expected:200,limit:0),
        let lengthText=head.value(forHTTPHeaderField:"Content-Length"),
        let size=Int64(lengthText),size>0 else{throw FilmMaterialExportFailure.remoteUnavailable}
  progress(0.3)
  let chunk:Int64=min(65_536,size)
  let firstRange="bytes=0-\(chunk-1)"
  guard let (first,firstResponse)=load(request("GET",range:firstRange),expected:206,limit:Int(chunk)),
        first.count==Int(chunk),
        firstResponse.value(forHTTPHeaderField:"Content-Range")?.hasSuffix("/\(size)")==true else {
   throw FilmMaterialExportFailure.remoteUnavailable
  }
  progress(0.65)
  let lastRange="bytes=\(size-chunk)-\(size-1)"
  guard let (last,lastResponse)=load(request("GET",range:lastRange),expected:206,limit:Int(chunk)),
        last.count==Int(chunk),
        lastResponse.value(forHTTPHeaderField:"Content-Range")?.hasSuffix("/\(size)")==true else {
   throw FilmMaterialExportFailure.remoteUnavailable
  }
  progress(1)
  return remoteIdentity(url,head:head,size:size,first:first,last:last)
 }
 static func remoteAsync(_ url:URL,session:URLSession = .shared,progress:(Double)->Void={_ in})async throws->String {
  guard ["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil else {
   throw FilmMaterialExportFailure.localFileRequired
  }
  try Task.checkCancellation()
  func request(_ method:String,range:String?=nil)->URLRequest {
   var result=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:45)
   result.httpMethod=method
   if let range {result.setValue(range,forHTTPHeaderField:"Range")}
   return result
  }
  func load(_ request:URLRequest,expected:Int,limit:Int) async throws->(Data,HTTPURLResponse)? {
   // URLSession range requests must stay bounded. A non-range server can
   // return the whole 50 GB movie; refuse it before receiving its body.
   let reader=FilmMaterialRangeRequest(limit:limit,expectedStatus:expected)
   return try await reader.fetchAsync(request:request,configuration:session.configuration)
  }
  guard let (_,head)=try await load(request("HEAD"),expected:200,limit:0),
        let lengthText=head.value(forHTTPHeaderField:"Content-Length"),
        let size=Int64(lengthText),size>0 else{throw FilmMaterialExportFailure.remoteUnavailable}
  progress(0.3)
  let chunk:Int64=min(65_536,size)
  let firstRange="bytes=0-\(chunk-1)"
  guard let (first,firstResponse)=try await load(request("GET",range:firstRange),expected:206,limit:Int(chunk)),
        first.count==Int(chunk),
        firstResponse.value(forHTTPHeaderField:"Content-Range")?.hasSuffix("/\(size)")==true else {
   throw FilmMaterialExportFailure.remoteUnavailable
  }
  progress(0.65)
  let lastRange="bytes=\(size-chunk)-\(size-1)"
  guard let (last,lastResponse)=try await load(request("GET",range:lastRange),expected:206,limit:Int(chunk)),
        last.count==Int(chunk),
        lastResponse.value(forHTTPHeaderField:"Content-Range")?.hasSuffix("/\(size)")==true else {
   throw FilmMaterialExportFailure.remoteUnavailable
  }
  progress(1)
  return remoteIdentity(url,head:head,size:size,first:first,last:last)
 }
 private static func remoteIdentity(_ url:URL,head:HTTPURLResponse,size:Int64,first:Data,last:Data)->String {
  var identity=URLComponents(url:url,resolvingAgainstBaseURL:false)
  identity?.query=nil;identity?.fragment=nil;identity?.user=nil;identity?.password=nil
  var hash=SHA256()
  hash.update(data:Data("togetherplayer-http-range-v1\n".utf8))
  hash.update(data:Data((identity?.string ?? url.path).utf8))
  hash.update(data:Data("\n\(size)\n".utf8))
  hash.update(data:Data((head.value(forHTTPHeaderField:"ETag") ?? "").utf8))
  hash.update(data:Data((head.value(forHTTPHeaderField:"Last-Modified") ?? "").utf8))
  hash.update(data:first);hash.update(data:last)
  return hash.finalize().map{String(format:"%02x",$0)}.joined()
 }
 // Candidate lookup only; never accepted as a strict source match.
 static func candidate(_ url:URL)throws->String {
  if !url.isFileURL {return try remote(url)}
  let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
  let size=try handle.seekToEnd();try handle.seek(toOffset:0)
  let first=try handle.read(upToCount:65_536) ?? Data()
  try handle.seek(toOffset:size>65_536 ? size-65_536 : 0)
  let last=try handle.read(upToCount:65_536) ?? Data()
  var hash=SHA256();hash.update(data:Data(String(size).utf8));hash.update(data:first);hash.update(data:last)
  return hash.finalize().map{String(format:"%02x",$0)}.joined()
 }
 static func subtitles(_ srt:String)->String {
  SHA256.hash(data:Data(srt.utf8)).map{String(format:"%02x",$0)}.joined()
 }
}

enum FilmMaterialZip {
 private static func u16(_ n:UInt16,into d:inout Data) {d.append(UInt8(n & 255));d.append(UInt8((n>>8)&255))}
 private static func u32(_ n:UInt32,into d:inout Data) {
  d.append(UInt8(n&255));d.append(UInt8((n>>8)&255));d.append(UInt8((n>>16)&255));d.append(UInt8((n>>24)&255))
 }
 // zlib implements the same ZIP/IEEE CRC, including its initial/final XOR.
 // Keep streaming in bounded blocks; avoid eight Swift bit operations per byte.
 private static func crc(_ data:Data,startingAt checksum:UInt32=0)->UInt32 {
  data.withUnsafeBytes {bytes in
   UInt32(crc32(uLong(checksum),bytes.bindMemory(to:Bytef.self).baseAddress,uInt(bytes.count)))
  }
 }
 // Write one bounded block at a time. Neither all sheets nor the completed
 // archive need to coexist in RAM alongside the playing movie and OCR model.
 static let blockSize=64*1024
 static func write(_ entries:[(String,URL)],to output:URL,onChunk:()->Void={})throws {
  guard entries.count<=255 else{throw FilmMaterialExportFailure.tooManyFiles}
  guard FileManager.default.createFile(atPath:output.path,contents:nil) else{throw FilmMaterialExportFailure.tooManyFiles}
  let writer=try FileHandle(forWritingTo:output)
  var finished=false
  defer {try? writer.close();if !finished {try? FileManager.default.removeItem(at:output)}}
  var central=Data(),offset:UInt32=0
  func scan(_ file:URL,_ consume:(Data)throws->Void)throws {
   let reader=try FileHandle(forReadingFrom:file);defer{try? reader.close()}
   while true {
    let count=try autoreleasepool {() throws->Int in
     try Task.checkCancellation()
     let block=try reader.read(upToCount:blockSize) ?? Data()
     if !block.isEmpty {try consume(block);onChunk()}
     return block.count
    }
    if count==0 {break}
   }
  }
  for (path,file) in entries {
   try Task.checkCancellation()
   let name=Data(path.utf8)
   guard !name.isEmpty,name.count<Int(UInt16.max),!path.contains(".."),!path.hasPrefix("/") else{throw FilmMaterialExportFailure.tooManyFiles}
   var checksum:UInt32=0,size=0
   try scan(file) {block in
    size+=block.count
    guard size<20_000_000 else{throw FilmMaterialExportFailure.tooManyFiles}
    checksum=crc(block,startingAt:checksum)
   }
   guard UInt64(offset)+UInt64(size)+UInt64(name.count)+30<=150_000_000 else{throw FilmMaterialExportFailure.tooManyFiles}
   var header=Data()
   u32(0x04034b50,into:&header);u16(20,into:&header);u16(0x0800,into:&header);u16(0,into:&header)
   u16(0,into:&header);u16(0,into:&header);u32(checksum,into:&header);u32(UInt32(size),into:&header);u32(UInt32(size),into:&header)
   u16(UInt16(name.count),into:&header);u16(0,into:&header);header.append(name)
   try writer.write(contentsOf:header)
   var written=0
   try scan(file) {block in written+=block.count;guard written<=size else{throw FilmMaterialExportFailure.sourceChanged};try writer.write(contentsOf:block)}
   guard written==size else{throw FilmMaterialExportFailure.sourceChanged}
   u32(0x02014b50,into:&central);u16(20,into:&central);u16(20,into:&central)
   u16(0x0800,into:&central);u16(0,into:&central);u16(0,into:&central);u16(0,into:&central)
   u32(checksum,into:&central);u32(UInt32(size),into:&central);u32(UInt32(size),into:&central)
   u16(UInt16(name.count),into:&central);u16(0,into:&central);u16(0,into:&central)
   u16(0,into:&central);u16(0,into:&central);u32(0,into:&central);u32(offset,into:&central);central.append(name)
   offset+=UInt32(header.count+size)
  }
  try Task.checkCancellation()
  let centralSize=central.count
  u32(0x06054b50,into:&central);u16(0,into:&central);u16(0,into:&central)
  u16(UInt16(entries.count),into:&central);u16(UInt16(entries.count),into:&central)
  u32(UInt32(centralSize),into:&central);u32(offset,into:&central);u16(0,into:&central)
  try writer.write(contentsOf:central);finished=true
 }
 // Standard ZIP store-only format: already-compressed JPGs need no recompression.
 static func make(_ entries:[(String,Data)])->Data? {
  guard entries.count<=255 else{return nil}
  var result=Data();var central=Data()
  for (path,data) in entries {
   let name=Data(path.utf8)
   guard !name.isEmpty,name.count<Int(UInt16.max),!path.contains(".."),
     !path.hasPrefix("/"),data.count<20_000_000,result.count<150_000_000 else{return nil}
   let offset=UInt32(result.count),size=UInt32(data.count),checksum=crc(data)
   u32(0x04034b50,into:&result);u16(20,into:&result);u16(0x0800,into:&result);u16(0,into:&result)
   u16(0,into:&result);u16(0,into:&result);u32(checksum,into:&result);u32(size,into:&result);u32(size,into:&result)
   u16(UInt16(name.count),into:&result);u16(0,into:&result);result.append(name);result.append(data)
   u32(0x02014b50,into:&central);u16(20,into:&central);u16(20,into:&central)
   u16(0x0800,into:&central);u16(0,into:&central);u16(0,into:&central);u16(0,into:&central)
   u32(checksum,into:&central);u32(size,into:&central);u32(size,into:&central)
   u16(UInt16(name.count),into:&central);u16(0,into:&central);u16(0,into:&central)
   u16(0,into:&central);u16(0,into:&central);u32(0,into:&central);u32(offset,into:&central);central.append(name)
  }
  let centralOffset=UInt32(result.count)
  result.append(central)
  u32(0x06054b50,into:&result);u16(0,into:&result);u16(0,into:&result)
  u16(UInt16(entries.count),into:&result);u16(UInt16(entries.count),into:&result)
  u32(UInt32(central.count),into:&result);u32(centralOffset,into:&result);u16(0,into:&result)
  return result
 }
}

enum FilmMaterialExportGate {
 private static let lock=NSLock()
 static func exclusively<T>(_ body:()throws->T)throws->T {
  // Cancellation of a Task is cooperative. A second tap/movie must not open a
  // second full decoder while the previous Vision/FFmpeg call is unwinding.
  guard lock.try() else{throw FilmMaterialExportFailure.busy}
  defer{lock.unlock()};return try body()
 }
}

enum FilmMaterialExportStage:String {
 case fingerprint="核对原片",subtitles="读取完整字幕 / PGS OCR",frames="全片采样",tail="片尾加密",boundary="边界补采",archive="保存素材与打包"
}

enum FilmMaterialExporter {
 static func selectedTimes(duration:Double,subtitles:SubtitleDocument)->[Double] {
  guard duration.isFinite,duration>=60 else{return []}
  let baseline=Array(stride(from:10.0,through:max(10,duration-10),by:60))
  // Prioritize long gaps between dialogue as potential visual storytelling.
  let cues=subtitles.cues
  var gaps:[(Double,Double)]=[]
  if cues.count>1 {
   for i in 1..<cues.count {
    let gap=cues[i].start-cues[i-1].end
    if gap>=20,gap<300 {gaps.append(((cues[i-1].end+cues[i].start)/2,gap))}
   }
  }
  let additions=gaps.sorted{$0.1>$1.1}.prefix(40).flatMap{gap in [gap.0-2,gap.0,gap.0+2]}
  // Subtitle-density changes and decisions are heuristic sampling hints, not
  // claims that this app already understands an action or a visual twist.
  let changes=cues.enumerated().filter{index,cue in
   index>0 && index%7==0 && (cue.text.contains("？") || cue.text.contains("!") || cue.start-cues[index-1].end>8)
  }.prefix(25).flatMap{[max(0,$0.element.start-1.5),$0.element.end+1.5]}
  var selected:[Double]=[]
  for t in (baseline+additions+changes).sorted() {
   if t>=0,t<duration,selected.last.map({t-$0>=0.8}) ?? true {selected.append(t)}
  }
  // Cover the whole film even if the optional hints exceed the total cap.
  if selected.count>250 {return (0..<250).map{selected[$0*(selected.count-1)/249]}}
  return selected
 }

 private static func contactSheet(_ frames:[(Double,CGImage)])->Data? {
  guard !frames.isEmpty else{return nil}
  let columns=4,cellW=250,cellH=165
  let rows=(frames.count+columns-1)/columns
  let format=UIGraphicsImageRendererFormat();format.preferredRange = .standard;format.scale=1
  let renderer=UIGraphicsImageRenderer(size:CGSize(width:columns*cellW,height:rows*cellH),format:format)
  let image=renderer.image { context in
   UIColor.black.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:columns*cellW,height:rows*cellH))
   for (index,value) in frames.enumerated() {
    let x=(index%columns)*cellW,y=(index/columns)*cellH
    let image=UIImage(cgImage:value.1)
    let scale=min(Double(cellW)/Double(image.size.width),Double(cellH-25)/Double(image.size.height))
    let width=Double(image.size.width)*scale,height=Double(image.size.height)*scale
    image.draw(in:CGRect(x:Double(x)+(Double(cellW)-width)/2,y:Double(y)+(Double(cellH-25)-height)/2,width:width,height:height))
    let totalMs=Int((value.0*1000).rounded())
    let seconds=totalMs/1000
    let timestamp=String(format:"%02d:%02d:%02d.%03d",seconds/3600,(seconds/60)%60,seconds%60,totalMs%1000)
    let text=timestamp as NSString
    text.draw(at:CGPoint(x:x+8,y:y+cellH-23),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:15,weight:.semibold),.foregroundColor:UIColor.white])
   }
  }
  return image.jpegData(compressionQuality:0.76)
 }
 static func create(url:URL,title:String,external:SubtitleDocument?,allowOCR:Bool,preferredTitle:String?=nil,preferredLanguage:String?=nil,preferredStreamIndex:Int?=nil,preferredDurationSeconds:Double?=nil,progress:@escaping (Double)->Void,stage:@escaping (FilmMaterialExportStage)->Void={_ in})throws->URL {
  try FilmMaterialExportGate.exclusively {
   try createExclusive(url:url,title:title,external:external,allowOCR:allowOCR,preferredTitle:preferredTitle,preferredLanguage:preferredLanguage,preferredStreamIndex:preferredStreamIndex,preferredDurationSeconds:preferredDurationSeconds,progress:progress,stage:stage)
  }
 }
 private static func createExclusive(url:URL,title:String,external:SubtitleDocument?,allowOCR:Bool,preferredTitle:String?,preferredLanguage:String?,preferredStreamIndex:Int?,preferredDurationSeconds:Double?,progress:@escaping (Double)->Void,stage:(FilmMaterialExportStage)->Void)throws->URL {
  try Task.checkCancellation()
  guard url.isFileURL || ["http","https"].contains(url.scheme?.lowercased() ?? "") else{throw FilmMaterialExportFailure.localFileRequired}
  let scoped=url.isFileURL && url.startAccessingSecurityScopedResource()
  defer {if scoped {url.stopAccessingSecurityScopedResource()}}
  if url.isFileURL && !FileManager.default.isReadableFile(atPath:url.path) {throw FilmMaterialExportFailure.localFileRequired}
  let attributes=try url.isFileURL ? url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]) : nil
  stage(.fingerprint)
  let fingerprint=try FilmMaterialFingerprint.source(url,progress:{progress($0*0.05)})
  stage(.subtitles)
  let extracted:FullFilmTranscriptReader.Output?
  if external != nil {
   // Explicit imported subtitles win; never rescan embedded subtitles.
   extracted=nil;progress(0.30)
  } else {
   extracted=try FullFilmTranscriptReader.extract(url,preferredTitle:preferredTitle,preferredLanguage:preferredLanguage,preferredStreamIndex:preferredStreamIndex,allowOCR:allowOCR,progress:{value in progress(0.05+value*0.25)})
  }
  try Task.checkCancellation()
  guard let subtitles=external ?? extracted?.document else{throw FilmMaterialExportFailure.missingSubtitles}
  let srt=SubtitleSRTEncoder.encode(subtitles)
  guard !srt.isEmpty else{throw FilmMaterialExportFailure.missingSubtitles}
  let asset=AVURLAsset(url:url)
  let assetDuration=url.isFileURL ? asset.duration.seconds : 0
  // The remuxed live player may know the original MKV duration before AVURLAsset.
  let supplied=preferredDurationSeconds ?? 0
  let duration=extracted?.duration ?? (supplied.isFinite && supplied>=60 ? supplied : (assetDuration.isFinite && assetDuration>0 ? assetDuration : FilmFFmpegFrameSampler.mediaDuration(url) ?? 0))
  guard duration.isFinite,duration>=60,duration<=43_200 else{throw FilmMaterialExportFailure.missingDuration}
  let times=selectedTimes(duration:duration,subtitles:subtitles)
  let generator=AVAssetImageGenerator(asset:asset)
  generator.appliesPreferredTrackTransform=true
  if #available(iOS 18.0,*) {generator.dynamicRangePolicy = .forceSDR}
  generator.maximumSize=CGSize(width:500,height:300)
  generator.requestedTimeToleranceBefore=CMTime(seconds:1,preferredTimescale:600)
  generator.requestedTimeToleranceAfter=CMTime(seconds:1,preferredTimescale:600)
  let document=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("AI素材",isDirectory:true)
  try FileManager.default.createDirectory(at:document,withIntermediateDirectories:true)
  let staging=document.appendingPathComponent(".export-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:staging.appendingPathComponent("contact-sheets"),withIntermediateDirectories:true)
  var installed=false
  defer {if !installed {try? FileManager.default.removeItem(at:staging)}}
  var sheets:[String]=[]
  var pending:[(Double,CGImage)]=[]
  var frameTimes:[Int]=[]
  var timeline:[FilmFrameRecord]=[]
  // AVAssetImageGenerator cannot decode many MKV/HEVC containers directly.
  // Use the already-shipped FFmpeg libraries for local, independent decoding.
  let directFFmpeg = !url.isFileURL || ["mkv","webm","ts","m2ts","avi"].contains(url.pathExtension.lowercased())
  var ffmpegOpenFailure:String?
  var ffmpeg:FilmFFmpegFrameSampler?=directFFmpeg ? FilmFFmpegFrameSampler.openCoordinated(url:url,onFailure:{ffmpegOpenFailure=$0}) : nil
  var attempted:Set<Int>=[],successful:Set<Int>=[],previousSignature:[Double]?,previousRequested:Double?
  var failures:[Int:FilmFrameFailure]=[:]
  var creditSignals:[(Int,Bool)]=[]
  var phase=FilmMaterialExportStage.frames
  var phaseInterval=60.0
  var lastFrameError:String?
  var nativeFrameProbeTried=false,nativeFrameProbeWorks=false
  func decode(_ time:Double)->(Double,CGImage)? {
   let requestedMs=Int((time*1000).rounded())
   attempted.insert(requestedMs)
   guard !Task.isCancelled else{return nil}
   var image:CGImage?,actualTime=Double.nan
   if directFFmpeg {
    image=ffmpeg?.image(at:time,reuseDecoder:phase == .tail || phase == .boundary)
    actualTime=ffmpeg?.lastDecodedTime ?? .nan
    if image==nil {
     lastFrameError=ffmpeg?.lastFailure ?? ffmpegOpenFailure ?? "FFmpeg无法打开MKV视频轨道"
     if url.isFileURL && (!nativeFrameProbeTried || nativeFrameProbeWorks) {
      nativeFrameProbeTried=true
      var nativeActual=CMTime.invalid
      let nativeImage=try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:&nativeActual)
      if let nativeImage,nativeActual.isValid,nativeActual.seconds.isFinite,nativeActual.seconds>=0 {
       image=nativeImage;actualTime=nativeActual.seconds;nativeFrameProbeWorks=true
      } else {nativeFrameProbeWorks=false}
     }
    }
   } else {
    var nativeActual=CMTime.invalid
    image=try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:&nativeActual)
    if nativeActual.isValid,nativeActual.seconds.isFinite {actualTime=nativeActual.seconds} else {image=nil}
    if image==nil {
     if ffmpeg==nil {ffmpeg=FilmFFmpegFrameSampler.openCoordinated(url:url,onFailure:{ffmpegOpenFailure=$0})}
     image=ffmpeg?.image(at:time);actualTime=ffmpeg?.lastDecodedTime ?? .nan
    }
   }
   func invalid(_ timestamp:Double,_ picture:CGImage?)->String? {
    guard picture != nil,timestamp.isFinite,timestamp>=0,timestamp<=duration else{return lastFrameError ?? ffmpeg?.lastFailure ?? ffmpegOpenFailure ?? "视频未返回有效帧时间戳"}
    let actualMs=Int((timestamp*1000).rounded())
    let history=timeline.map{($0.requestedMs,$0.actualMs)}
    if let reason=FilmFrameTimeGate.rejection(requestedMs:requestedMs,actualMs:actualMs,intervalMs:Int(phaseInterval*1000),
      previous:history,durationMs:Int(duration*1000)) {
     return reason+"（请求\(requestedMs)ms，实际\(actualMs)ms）"
    }
    return nil
   }
   var reason=invalid(actualTime,image)
   if reason != nil {
    // Exact native seek followed by an FFmpeg backward/preroll decode. The
    // latter uses real decoded PTS and never fabricates the requested time.
    if !directFFmpeg {
     generator.requestedTimeToleranceBefore = .zero
     generator.requestedTimeToleranceAfter = .zero
     var actual=CMTime.invalid
     let exact=try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:&actual)
     if let exact,actual.isValid {image=exact;actualTime=actual.seconds}
    }
    if invalid(actualTime,image) != nil {
     if ffmpeg==nil {ffmpeg=FilmFFmpegFrameSampler.openCoordinated(url:url,onFailure:{ffmpegOpenFailure=$0})}
     image=ffmpeg?.image(at:time,seekBackSeconds:4)
     actualTime=ffmpeg?.lastDecodedTime ?? .nan
    }
    reason=invalid(actualTime,image)
   }
   if let reason {
    let width=Int(max(0.5,phaseInterval/2)*1000)
    failures[requestedMs]=FilmFrameFailure(startMs:max(0,requestedMs-width),endMs:min(Int(duration*1000),requestedMs+width),requestedMs:requestedMs,reason:reason,returnedActualMs:actualTime.isFinite ? Int((actualTime*1000).rounded()) : nil)
    lastFrameError=reason
    return nil
   }
   guard let image else{return nil}
   failures.removeValue(forKey:requestedMs)
   return (actualTime,image)
  }
  func saveSheet()throws {
   try autoreleasepool {
    try Task.checkCancellation()
    guard let bytes=contactSheet(pending) else{throw FilmMaterialExportFailure.framesUnavailable}
    let path=String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1)
    try bytes.write(to:staging.appendingPathComponent(path),options:.atomic)
    sheets.append(path);pending.removeAll(keepingCapacity:true)
   }
  }
  func append(_ value:(Double,CGImage),requested:Double,score:Double?,reason:String)throws {
   let actualMs=Int((value.0*1000).rounded())
   timeline.append(FilmFrameRecord(requestedMs:Int((requested*1000).rounded()),actualMs:actualMs,sheet:String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1),row:pending.count/4,column:pending.count%4,visualEvidenceComplete:false,sceneChangeScore:score,samplingReason:reason))
   pending.append(value);frameTimes.append(actualMs);successful.insert(Int((requested*1000).rounded()))
   if pending.count==16 {try saveSheet()}
  }
  stage(.frames)
  for (index,time) in times.enumerated() {
   try Task.checkCancellation()
   try autoreleasepool {
    phase = .frames;phaseInterval = 60
    let decoded=decode(time)
    if directFFmpeg && ffmpeg == nil && nativeFrameProbeTried && !nativeFrameProbeWorks {
     throw FilmMaterialExportFailure.frameExtractionDiagnostic("FFmpeg 初始化失败；"+(ffmpegOpenFailure ?? "未知视频解码初始化故障")+"；系统原生解码也未取得画面")
    }
    if let main=decoded {
     let signature=FilmSceneChange.signature(main.1)
     let score=FilmSceneChange.distance(previousSignature,signature)
     let nextTime=index+1<times.count ? times[index+1] : duration
     // Reserve room for whole-film dialogue and interval samples.
     let extraRoom=250-attempted.count-(times.count-index-1)
     let supplement=score.map{$0>0.55}==true && extraRoom>=2 && time-(previousRequested ?? time)>=10
     if supplement,time-2>(previousRequested ?? 0)+0.8,let before=decode(time-2) {try append(before,requested:time-2,score:score,reason:"visual-change-before")}
     try append(main,requested:time,score:score,reason:"whole-film-interval-caption-or-dialogue-gap")
     if supplement,time+2<nextTime-0.8,time+2<duration,let after=decode(time+2) {try append(after,requested:time+2,score:score,reason:"visual-change-after")}
     previousSignature=signature;previousRequested=time
    }
   }
   if index%5==0 {progress(0.30+0.29*Double(index+1)/Double(max(1,times.count)))}
  }
  // A separate tail phase is NEVER downsampled by the old 250-frame cap.
  // Sample all the way to EOF, including the regions after the first credits.
  stage(.tail);phase = .tail;phaseInterval = FilmTailSamplingPlan.interval
  let tailStart=FilmTailSamplingPlan.start(duration:duration)
  let dense=FilmTailSamplingPlan.dense(duration:duration)
  func tailFrame(_ t:Double,reason:String)throws {
   try Task.checkCancellation()
   let key=Int((t*1000).rounded())
   guard !successful.contains(key) else{return}
   try autoreleasepool {
    if let picture=decode(t) {
     creditSignals.append((key,FilmCreditsDetector.isCreditsLike(picture.1)))
     try append(picture,requested:t,score:nil,reason:reason)
    }
   }
  }
  for (index,t) in dense.enumerated() {
   try tailFrame(t,reason:"tail-2s")
   if index%5==0 {progress(0.59+0.29*Double(index+1)/Double(max(1,dense.count)))}
  }
  var expandedStart=tailStart
  // A credits run present at the beginning of the priority window might
  // have begun much earlier. Expand backward until non-credit evidence
  // appears, or reach the start of the actual media.
  let leading=creditSignals.filter{$0.0<Int((tailStart+12)*1000)}.sorted{$0.0<$1.0}
  if leading.prefix(3).filter({$0.1}).count>=2 {
   var foundPrecedingScene=false
   while expandedStart>0 && !foundPrecedingScene {
    try Task.checkCancellation()
    let earlier=FilmTailSamplingPlan.backward(from:expandedStart)
    let previous=creditSignals.count
    for t in earlier {try tailFrame(t,reason:"credits-backward-extension")}
    expandedStart=max(0,expandedStart-60)
    let sampled=creditSignals.dropFirst(previous).sorted{$0.0<$1.0}
    var quiet=0
    for signal in sampled.reversed() {
     quiet=signal.1 ? 0 : quiet+1
     if quiet>=3 {foundPrecedingScene=true;break}
    }
   }
  }
  let candidates=FilmCreditsDetector.candidates(creditSignals)
  stage(.boundary);phase = .boundary;phaseInterval = 0.5
  let boundaryPoints=Array(Set(candidates.flatMap{FilmTailSamplingPlan.boundary(at:Double($0.atMs)/1000,duration:duration).map{Int(($0*1000).rounded())}})).sorted()
  for (index,key) in boundaryPoints.enumerated() {
   try Task.checkCancellation()
   if !successful.contains(key) {
    try autoreleasepool {
     if let value=decode(Double(key)/1000) {try append(value,requested:Double(key)/1000,score:nil,reason:"credits-transition-0.5s")}
    }
   }
   if index%5==0 {progress(0.88+0.08*Double(index+1)/Double(max(1,boundaryPoints.count)))}
  }
  try Task.checkCancellation()
  if !pending.isEmpty {try saveSheet()}
  pending.removeAll();ffmpeg=nil;generator.cancelAllCGImageGeneration()
  // We cannot claim to have understood the film's images if sampling failed.
  guard frameTimes.count>=min(4,times.count),
   Double(successful.count)>=Double(attempted.count)*0.80 else{
    throw FilmMaterialExportFailure.frameExtractionDiagnostic("实际画面\(successful.count)/\(attempted.count)；"+(lastFrameError ?? "视频轨道无法解码"))
   }
  stage(.archive);progress(0.96)
  var inspection=FilmEndingInspection(formatVersion:1,durationMs:Int((duration*1000).rounded()),
    priorityStartMs:Int((tailStart*1000).rounded()),inspectedRangesMs:[[Int((expandedStart*1000).rounded()),Int((duration*1000).rounded())]],
    creditCandidates:candidates,failedIntervals:failures.values.sorted{$0.requestedMs<$1.requestedMs},
    unverifiedRangesMs:[[Int(tailStart*1000),Int(duration*1000)]] +
      candidates.map{[max(0,$0.atMs-5000),min(Int(duration*1000),$0.atMs+5000)]},
    storyEndMs:nil,storyEndStatus:"unverified: visual credit detection cannot establish the last required story scene or rule out post-credit material",
    samplingPolicy:"full-film interval + dialogue gaps + scene changes; final 720 seconds every 2s; credits transitions ±5s every 0.5s; credits until EOF")
  inspection.unverifiedRangesMs += inspection.failedIntervals.map{[$0.startMs,$0.endMs]}
  var manifest=FilmMaterialManifest(schemaVersion:1,title:String(title.prefix(180)),durationMs:Int((duration*1000).rounded()),sourceFingerprint:fingerprint,subtitleFingerprint:FilmMaterialFingerprint.subtitles(srt),subtitleCueCount:subtitles.cues.count,frameCount:frameTimes.count,contactSheets:sheets,frameTimesMs:frameTimes.sorted(),frameExportMode:"AVFoundation SDR / FFmpeg PQ-HLG tone map; whole-film interval and scene-change, tail 2s, transition 0.5s; actual decoded PTS; story end unverified",requestedFrameCount:attempted.count,missingFrameTimesMs:Array(attempted.subtracting(successful)).sorted())
  if !url.isFileURL {manifest.fingerprintAlgorithm="sha256-sparse-http-range-v1"}
  let enc=JSONEncoder();enc.outputFormatting=[.prettyPrinted,.sortedKeys]
  let info=try enc.encode(manifest)
  var endingDictionary=(try JSONSerialization.jsonObject(with:enc.encode(inspection))) as? [String:Any] ?? [:]
  endingDictionary["storyEndMs"]=NSNull()  // Explicit null, never an invented ending timestamp.
  let endingData=try JSONSerialization.data(withJSONObject:endingDictionary,options:[.prettyPrinted,.sortedKeys])
  let instructions="TogetherPlayer 电影素材包 v1\n本包含完整字幕、分镜图及时间轴。ChatGPT 必须根据这部影片的主类型与实际副类型选取独立出题指南，制作有片内证据、不跑题的个性化互动问题。\n使用 ChatGPT项目指令.txt 和 genres 文件夹内的 21 类电影独立规则。多类型电影按真实情节混合，而不是一律套用侦探题。\n静态截图不能证明缺失片段的动作；缺少素材时先补齐，不要编造。\n生成 JSON 时使用正式Schema，影片指纹和时长从 manifest.json 原样复制，并包含完整 filmReview 片尾解读。\n"
  let schemaURL=Bundle.main.url(forResource:"question-bank-v1.schema",withExtension:"json")
  guard let schemaURL else{throw FilmBankValidation.detail("安装包缺少正式题库Schema，素材未发布。")}
  let schema=try Data(contentsOf:schemaURL)
  let projectGuide=FilmBankProjectInstructions.text
  let sourceNote=url.isFileURL ? "原片指纹采用完整文件SHA256" : "U盘 HTTP 原片使用首尾分段与 HTTP 元数据指纹（sha256-sparse-http-range-v1），是轻量识别而非完整文件SHA256；请使用同一片源链接导入题库"
  let entries:[(String,Data)]=[("manifest.json",info),("ending-inspection.json",endingData),("subtitles/whole-film.srt",Data(srt.utf8)),("frame-timeline.json",try enc.encode(timeline.sorted{$0.actualMs<$1.actualMs})),("question-bank-v1.schema.json",schema),("ChatGPT项目指令.txt",Data(projectGuide.utf8)),("README.txt",Data((instructions+"\n"+sourceNote+"；画面时间轴的actualMs是实际解码时间，截图不是连续动作证据。结尾分析见 ending-inspection.json；storyEndMs 为 null 时必须人工验证候选边界与所有片尾彩蛋。\n可单独分享SRT、manifest、Schema和所有分镜JPG；不要只提供影片名称。\n").utf8))]+FilmBankGenreInstructions.exportFiles
  let name=url.deletingPathExtension().lastPathComponent
   .replacingOccurrences(of:"[^a-zA-Z0-9_\\-一-龥]",with:"_",options:.regularExpression)
  let filename=String(name.prefix(52))
  let bundle=document.appendingPathComponent(filename+"-"+String(fingerprint.prefix(12))+"-"+String(UUID().uuidString.prefix(8)),isDirectory:true)
  for (path,data) in entries {
   try Task.checkCancellation()
   let file=staging.appendingPathComponent(path)
   try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
   try data.write(to:file,options:.atomic)
  }
  let paths=entries.map{$0.0}+sheets
  try FilmMaterialZip.write(paths.map{($0,staging.appendingPathComponent($0))},to:staging.appendingPathComponent("电影_AI素材.zip"))
  try Task.checkCancellation()
  if let attributes {
   let finalAttributes=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
   guard attributes.fileSize==finalAttributes.fileSize,attributes.contentModificationDate==finalAttributes.contentModificationDate else{throw FilmMaterialExportFailure.sourceChanged}
  } else {
   guard fingerprint == (try FilmMaterialFingerprint.remote(url)) else{throw FilmMaterialExportFailure.sourceChanged}
  }
  try FileManager.default.moveItem(at:staging,to:bundle);installed=true
  progress(1)
  return bundle.appendingPathComponent("电影_AI素材.zip")
 }
}
struct FilmFrameRecord:Codable {
 let requestedMs:Int
 let actualMs:Int
 let sheet:String
 let row:Int
 let column:Int
 let visualEvidenceComplete:Bool
 var sceneChangeScore:Double?=nil
 var samplingReason:String="interval-caption-or-dialogue-gap"
}

@MainActor final class FilmMaterialExportSession:ObservableObject {
 @Published private(set) var working=false
 @Published private(set) var progress=0.0
 @Published private(set) var status="请先加载影片（支持本机与 U 盘 HTTP）"
 @Published private(set) var file:URL?
 @Published private(set) var individualFiles:[URL]=[]
 @Published private(set) var previewSubtitle=""
 private var generation=0
 private var source:URL?
 private var worker:Task<URL,Error>?
 private var memoryObserver:NSObjectProtocol?
 private let defaults:UserDefaults
 private static let checkpointKey="film-material-export-active-stage"
 private var currentStage:FilmMaterialExportStage?
 private var cancellationNote:String?
 init(defaults:UserDefaults = .standard) {
  self.defaults=defaults
  if let phase=defaults.string(forKey:Self.checkpointKey) {
   status="上次提取在“\(phase)”阶段中断；可以重试。"
  }
  memoryObserver=NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main) {[weak self] _ in
   Task {@MainActor [weak self] in self?.stopForMemoryPressure()}
  }
 }
 func selectMovie(_ url:URL?) {if source != url {cancel();source=url;file=nil;individualFiles=[];previewSubtitle="";status=url == nil ? "请先选择影片" : (url?.isFileURL == true ? "点击提取后在本机扫描原片字幕和画面" : "点击提取后通过 U 盘 HTTP 读取字幕和关键帧，不复制原片到 iPad")}}
 func invalidateSubtitleSelection() {
  guard !working else{return}
  generation+=1;worker?.cancel();worker=nil
  file=nil;individualFiles=[];previewSubtitle="";progress=0
  defaults.removeObject(forKey:Self.checkpointKey)
  status="字幕来源已更新，请重新导出 AI 素材（原有文件未删除）"
 }
 func cancel() {generation+=1;worker?.cancel();worker=nil;working=false;defaults.removeObject(forKey:Self.checkpointKey);status="已取消提取，未上传原片"}
 func stopForMemoryPressure() {
  guard working else{return}
  cancellationNote="设备内存紧张，已停止提取；请暂停影片后重试。原片和字幕未改变。"
  worker?.cancel();status=cancellationNote!
  // Keep working until the decoder/OCR returns and releases its resources.
 }
 func begin(url:URL?,title:String,external:SubtitleDocument?,allowOCR:Bool,preferredTitle:String?=nil,preferredLanguage:String?=nil,preferredStreamIndex:Int?=nil,preferredDurationSeconds:Double?=nil) {
  guard !working else{return}
  guard let url,url.isFileURL || ["http","https"].contains(url.scheme?.lowercased() ?? "") else{status=FilmMaterialExportFailure.localFileRequired.localizedDescription;return}
  selectMovie(url);generation+=1;let token=generation
  working=true;progress=0;file=nil;individualFiles=[];cancellationNote=nil;currentStage = .fingerprint
  defaults.set(FilmMaterialExportStage.fingerprint.rawValue,forKey:Self.checkpointKey)
  status=url.isFileURL ? "正在核对本地原片 0%（不复制原片）" : "正在核对 U 盘原片 0%（仅读取首尾少量数据）"
  let job=Task.detached(priority:.utility) {
   try FilmMaterialExporter.create(url:url,title:title,external:external,allowOCR:allowOCR,preferredTitle:preferredTitle,preferredLanguage:preferredLanguage,preferredStreamIndex:preferredStreamIndex,preferredDurationSeconds:preferredDurationSeconds,progress:{[weak self] value in
    Task {@MainActor in
     guard let self,self.generation==token,self.working,self.cancellationNote==nil else{return}
     self.progress=value
     if self.currentStage == .fingerprint {self.status="正在核对原片 \(Int(min(100,value/0.05*100)))%（"+(url.isFileURL ? "本地逐块校验" : "HTTP 分段校验")+"）"}
    }
   },stage:{[weak self] phase in
    Task {@MainActor in
     guard let self,self.generation==token,self.working,self.cancellationNote==nil else{return}
     self.currentStage=phase;self.status="正在"+phase.rawValue+"…"
     self.defaults.set(phase.rawValue,forKey:Self.checkpointKey)
    }
   })
  }
  worker=job
  Task {[weak self] in
   do {
    let output=try await job.value
    guard let self,self.generation==token,self.source==url else {
     try? FileManager.default.removeItem(at:output.deletingLastPathComponent());return
    }
    if self.cancellationNote != nil {try? FileManager.default.removeItem(at:output.deletingLastPathComponent());throw CancellationError()}
    let prepared=await Task.detached(priority:.utility){() -> ([URL],String) in
     let folder=output.deletingLastPathComponent()
     let all=(FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey])?.allObjects as? [URL]) ?? []
     return (all.filter{$0.pathExtension != "zip" && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}.sorted{$0.path<$1.path},String((try? String(contentsOf:folder.appendingPathComponent("subtitles/whole-film.srt"),encoding:.utf8))?.prefix(1800) ?? ""))
    }.value
    guard self.generation==token,self.cancellationNote==nil else{try? FileManager.default.removeItem(at:output.deletingLastPathComponent());throw CancellationError()}
    self.file=output;self.individualFiles=prepared.0;self.previewSubtitle=prepared.1
    self.status="素材已保存；可预览、分享ZIP或单独分享字幕与分镜。未上传原片。"
   } catch {
    guard let self,self.generation==token else{return}
    self.status=self.cancellationNote ?? (error is CancellationError ? "已取消提取，未上传原片" : "素材导出失败："+error.localizedDescription)
   }
   guard let self,self.generation==token else{return}
   self.worker=nil;self.working=false;self.defaults.removeObject(forKey:Self.checkpointKey)
  }
 }
 deinit {worker?.cancel();if let memoryObserver {NotificationCenter.default.removeObserver(memoryObserver)}}
}
