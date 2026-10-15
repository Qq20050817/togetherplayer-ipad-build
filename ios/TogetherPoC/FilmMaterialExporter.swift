import Foundation
import AVFoundation
import UIKit
import CryptoKit

// Offline, explicitly initiated export. No film, frames or subtitles are
// automatically transmitted to a server or to an AI provider.
enum FilmMaterialExportFailure:LocalizedError {
 case localFileRequired,missingSubtitles,framesUnavailable,missingDuration,tooManyFiles,sourceChanged
 var errorDescription:String? {switch self {
  case .localFileRequired:return "请先在 iPad“文件”中选择可读取的本地原片；网盘在线播放链接不支持直接导出原始画面。"
  case .missingSubtitles:return "未读取到完整字幕。可以先导入 SRT/ASS 字幕，再导出素材。"
  case .framesUnavailable:return "原片可读取字幕，但独立抽帧失败，未导出只有字幕的假完整素材。请使用可本地解码的影片文件。"
  case .missingDuration:return "无法确定影片时长，请确认原片完整。"
  case .sourceChanged:return "提取期间原片发生变化，本次素材已取消，请重新提取。"
  case .tooManyFiles:return "素材包超过安全容量，已取消导出。"
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
 let fingerprintAlgorithm="sha256-complete-file"
 let frameTimeline="frame-timeline.json"
 let requestedFrameCount:Int
 let missingFrameTimesMs:[Int]
}

enum FilmMaterialFingerprint {
 static func source(_ url:URL)throws->String {
  let handle=try FileHandle(forReadingFrom:url)
  defer {try? handle.close()}
  let size=try handle.seekToEnd()
  guard size>0 else{throw FilmMaterialExportFailure.localFileRequired}
  try handle.seek(toOffset:0)
  // Full file SHA256, not the old first/last 64 KiB sample. Two files with
  // altered middle bytes must not silently share a strict-version bank.
  var sha=SHA256(),read:UInt64=0
  while let bytes=try handle.read(upToCount:4*1024*1024),!bytes.isEmpty {
   try Task.checkCancellation();sha.update(data:bytes);read+=UInt64(bytes.count)
  }
  guard read==size,try handle.seekToEnd()==size else{throw FilmMaterialExportFailure.localFileRequired}
  return sha.finalize().map{String(format:"%02x",$0)}.joined()

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
 private static func crc(_ data:Data)->UInt32 {
  var c:UInt32=0xffffffff
  for b in data {c ^= UInt32(b);for _ in 0..<8 {c=(c>>1) ^ ((c&1)==1 ? 0xedb88320 : 0)}}
  return ~c
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
    let seconds=Int(value.0.rounded())
    let timestamp=String(format:"%02d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60)
    let text=timestamp as NSString
    text.draw(at:CGPoint(x:x+8,y:y+cellH-23),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:15,weight:.semibold),.foregroundColor:UIColor.white])
   }
  }
  return image.jpegData(compressionQuality:0.76)
 }
 static func create(url:URL,title:String,external:SubtitleDocument?,allowOCR:Bool,preferredTitle:String?=nil,preferredLanguage:String?=nil,preferredStreamIndex:Int?=nil,progress:@escaping (Double)->Void)throws->URL {
  guard url.isFileURL else{throw FilmMaterialExportFailure.localFileRequired}
  let scoped=url.startAccessingSecurityScopedResource()
  defer {if scoped {url.stopAccessingSecurityScopedResource()}}
  guard FileManager.default.isReadableFile(atPath:url.path) else{throw FilmMaterialExportFailure.localFileRequired}
  let attributes=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
  let fingerprint=try FilmMaterialFingerprint.source(url)
  let extracted:FullFilmTranscriptReader.Output?
  do {extracted=try FullFilmTranscriptReader.extract(url,preferredTitle:preferredTitle,preferredLanguage:preferredLanguage,preferredStreamIndex:preferredStreamIndex,allowOCR:allowOCR,progress:{value in progress(value*0.25)})}
  catch is CancellationError {throw CancellationError()}
  catch {guard external != nil else{throw error};extracted=nil}
  try Task.checkCancellation()
  guard let subtitles=extracted?.document ?? external else{throw FilmMaterialExportFailure.missingSubtitles}
  let srt=SubtitleSRTEncoder.encode(subtitles)
  guard !srt.isEmpty else{throw FilmMaterialExportFailure.missingSubtitles}
  let asset=AVURLAsset(url:url)
  let assetDuration=asset.duration.seconds
  let duration=extracted?.duration ?? (assetDuration.isFinite && assetDuration>0 ? assetDuration : FilmFFmpegFrameSampler.mediaDuration(url) ?? 0)
  guard duration.isFinite,duration>=60,duration<=43_200 else{throw FilmMaterialExportFailure.missingDuration}
  let times=selectedTimes(duration:duration,subtitles:subtitles)
  let generator=AVAssetImageGenerator(asset:asset)
  generator.appliesPreferredTrackTransform=true
  if #available(iOS 18.0,*) {generator.dynamicRangePolicy = .forceSDR}
  generator.maximumSize=CGSize(width:500,height:300)
  generator.requestedTimeToleranceBefore=CMTime(seconds:1,preferredTimescale:600)
  generator.requestedTimeToleranceAfter=CMTime(seconds:1,preferredTimescale:600)
  var sheets:[(String,Data)]=[]
  var pending:[(Double,CGImage)]=[]
  var frameTimes:[Int]=[]
  var timeline:[FilmFrameRecord]=[]
  // AVAssetImageGenerator cannot decode many MKV/HEVC containers directly.
  // Use the already-shipped FFmpeg libraries for local, independent decoding.
  let directFFmpeg=["mkv","webm","ts","m2ts","avi"].contains(url.pathExtension.lowercased())
  var ffmpeg:FilmFFmpegFrameSampler?=directFFmpeg ? FilmFFmpegFrameSampler(url:url) : nil
  var attempted:[Double]=[],previousSignature:[Double]?,previousRequested:Double?
  func decode(_ time:Double)->(Double,CGImage)? {
   attempted.append(time)
   guard !Task.isCancelled else{return nil}
   var image:CGImage?,actualTime=time
   if directFFmpeg {image=ffmpeg?.image(at:time);actualTime=ffmpeg?.lastDecodedTime ?? -1}
   else {
    var actual=CMTime.invalid
    image=try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:&actual)
    if actual.seconds.isFinite {actualTime=actual.seconds} else {image=nil}
    if image==nil {
     if ffmpeg==nil {ffmpeg=FilmFFmpegFrameSampler(url:url)}
     image=ffmpeg?.image(at:time);actualTime=ffmpeg?.lastDecodedTime ?? -1
    }
   }
   guard let image,actualTime.isFinite,actualTime>=0,actualTime<=duration else{return nil}
   return (actualTime,image)
  }
  func append(_ value:(Double,CGImage),requested:Double,score:Double?,reason:String)throws {
   let actualMs=Int((value.0*1000).rounded())
   timeline.append(FilmFrameRecord(requestedMs:Int((requested*1000).rounded()),actualMs:actualMs,sheet:String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1),row:pending.count/4,column:pending.count%4,visualEvidenceComplete:false,sceneChangeScore:score,samplingReason:reason))
   pending.append(value);frameTimes.append(actualMs)
   if pending.count==16 {
    guard let bytes=contactSheet(pending) else{throw FilmMaterialExportFailure.framesUnavailable}
    sheets.append((String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1),bytes));pending=[]
   }
  }
  for (index,time) in times.enumerated() {
   try Task.checkCancellation()
   if let main=decode(time) {
    let signature=FilmSceneChange.signature(main.1)
    let score=FilmSceneChange.distance(previousSignature,signature)
    let nextTime=index+1<times.count ? times[index+1] : duration
    // Heuristic visual change between sampled frames, not semantic shot
    // recognition. Reserve room for ALL remaining baseline samples.
    let extraRoom=250-attempted.count-(times.count-index-1)
    let supplement=score.map{$0>0.55}==true && extraRoom>=2 && time-(previousRequested ?? time)>=10
    if supplement,time-2>(previousRequested ?? 0)+0.8,let before=decode(time-2) {try append(before,requested:time-2,score:score,reason:"visual-change-before")}
    try append(main,requested:time,score:score,reason:"interval-caption-or-dialogue-gap")
    if supplement,time+2<nextTime-0.8,time+2<duration,let after=decode(time+2) {try append(after,requested:time+2,score:score,reason:"visual-change-after")}
    previousSignature=signature;previousRequested=time
   }
   if index%5==0 {progress(0.25+0.70*Double(index+1)/Double(max(1,times.count)))}
  }
  try Task.checkCancellation()
  if !pending.isEmpty {
   guard let bytes=contactSheet(pending) else{throw FilmMaterialExportFailure.framesUnavailable}
   sheets.append((String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1),bytes))
  }
  // We cannot claim to have understood the film's images if sampling failed.
  guard frameTimes.count>=min(4,times.count),
   Double(frameTimes.count)>=Double(attempted.count)*0.80 else{throw FilmMaterialExportFailure.framesUnavailable}
  let manifest=FilmMaterialManifest(schemaVersion:1,title:String(title.prefix(180)),durationMs:Int((duration*1000).rounded()),sourceFingerprint:fingerprint,subtitleFingerprint:FilmMaterialFingerprint.subtitles(srt),subtitleCueCount:subtitles.cues.count,frameCount:frameTimes.count,contactSheets:sheets.map{$0.0},frameTimesMs:frameTimes,frameExportMode:"AVFoundation SDR / FFmpeg PQ-HLG tone map; interval, dialogue-gap and sampled-histogram visual-change followups; incomplete motion evidence",requestedFrameCount:attempted.count,missingFrameTimesMs:attempted.map{Int(($0*1000).rounded())}.filter{requested in !timeline.contains{$0.requestedMs==requested}})
  let enc=JSONEncoder();enc.outputFormatting=[.prettyPrinted,.sortedKeys]
  let info=try enc.encode(manifest)
  let instructions="TogetherPlayer 电影素材包 v1\n本包含完整时间轴字幕、按时间顺序的多张分镜图以及严格对应的时间信息。\n请用 ChatGPT 项目指令制作 AI 题库。每道题提供已观看证据、未来揭晓依据、触发时间和安全答案揭晓时间。\n图片是离散截图，无法证明缺失画面之间的连续动作。不要编造未覆盖的视觉情节。\n生成 JSON 时 schemaVersion=1，影片 durationMs、sourceFingerprint、subtitleFingerprint 必须从 manifest.json 原样复制。\n题库还需通过 App 的校验再运行。\n"
  let schemaURL=Bundle.main.url(forResource:"question-bank-v1.schema",withExtension:"json")
  guard let schemaURL else{throw FilmBankValidation.detail("安装包缺少正式题库Schema，素材未发布。")}
  let schema=try Data(contentsOf:schemaURL)
  let projectGuide=FilmBankProjectInstructions.text
  var entries:[(String,Data)]=[("manifest.json",info),("subtitles/whole-film.srt",Data(srt.utf8)),("frame-timeline.json",try enc.encode(timeline)),("question-bank-v1.schema.json",schema),("ChatGPT项目指令.txt",Data(projectGuide.utf8)),("README.txt",Data((instructions+"\n原片指纹采用完整文件SHA256；画面时间轴的actualMs是实际解码时间，截图不是连续动作证据。\n可单独分享SRT、manifest、Schema和所有分镜JPG；不要只提供影片名称。\n").utf8))]
  entries.append(contentsOf:sheets)
  guard let archive=FilmMaterialZip.make(entries) else{throw FilmMaterialExportFailure.tooManyFiles}
  let document=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("AI素材",isDirectory:true)
  try FileManager.default.createDirectory(at:document,withIntermediateDirectories:true)
  let name=url.deletingPathExtension().lastPathComponent
   .replacingOccurrences(of:"[^a-zA-Z0-9_\\-一-龥]",with:"_",options:.regularExpression)
  let filename=String(name.prefix(52))
  let bundle=document.appendingPathComponent(filename+"-"+String(fingerprint.prefix(12))+"-"+String(UUID().uuidString.prefix(8)),isDirectory:true)
  let staging=document.appendingPathComponent(".export-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
  var installed=false
  defer {if !installed {try? FileManager.default.removeItem(at:staging)}}
  for (path,data) in entries {
   try Task.checkCancellation()
   let file=staging.appendingPathComponent(path)
   try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
   try data.write(to:file,options:.atomic)
  }
  try archive.write(to:staging.appendingPathComponent("电影_AI素材.zip"),options:.atomic)
  try Task.checkCancellation()
  let finalAttributes=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
  guard attributes.fileSize==finalAttributes.fileSize,attributes.contentModificationDate==finalAttributes.contentModificationDate else{throw FilmMaterialExportFailure.sourceChanged}
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
 @Published private(set) var status="请先加载本地原片"
 @Published private(set) var file:URL?
 @Published private(set) var individualFiles:[URL]=[]
 @Published private(set) var previewSubtitle=""
 private var generation=0
 private var source:URL?
 private var worker:Task<URL,Error>?
 func selectMovie(_ url:URL?) {if source != url {cancel();source=url;file=nil;individualFiles=[];previewSubtitle="";status="点击提取后，仅在本机扫描完整字幕和画面"}}
 func cancel() {generation+=1;worker?.cancel();worker=nil;working=false;status="已取消提取，未上传原片"}
 func begin(url:URL?,title:String,external:SubtitleDocument?,allowOCR:Bool,preferredTitle:String?=nil,preferredLanguage:String?=nil,preferredStreamIndex:Int?=nil) {
  guard !working else{return}
  guard let url,url.isFileURL else{status=FilmMaterialExportFailure.localFileRequired.localizedDescription;return}
  selectMovie(url);generation+=1;let token=generation
  working=true;progress=0;file=nil;individualFiles=[];status="正在提取全片字幕、分镜与精确时间轴…"
  let job=Task.detached(priority:.utility) {
   try FilmMaterialExporter.create(url:url,title:title,external:external,allowOCR:allowOCR,preferredTitle:preferredTitle,preferredLanguage:preferredLanguage,preferredStreamIndex:preferredStreamIndex,progress:{[weak self] value in
    Task {@MainActor in guard let self,self.generation==token else{return};self.progress=value}
   })
  }
  worker=job
  Task {[weak self] in
   do {
    let output=try await job.value
    guard let self,self.generation==token,self.source==url else {
     try? FileManager.default.removeItem(at:output.deletingLastPathComponent());return
    }
    let prepared=await Task.detached(priority:.utility){() -> ([URL],String) in
     let folder=output.deletingLastPathComponent()
     let all=(FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey])?.allObjects as? [URL]) ?? []
     return (all.filter{$0.pathExtension != "zip" && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}.sorted{$0.path<$1.path},String((try? String(contentsOf:folder.appendingPathComponent("subtitles/whole-film.srt"),encoding:.utf8))?.prefix(1800) ?? ""))
    }.value
    guard self.generation==token else{try? FileManager.default.removeItem(at:output.deletingLastPathComponent());return}
    self.file=output;self.individualFiles=prepared.0;self.previewSubtitle=prepared.1
    self.status="素材已保存；可预览、分享ZIP或单独分享字幕与分镜。未上传原片。"
   } catch {
    guard let self,self.generation==token else{return}
    self.status=error is CancellationError ? "已取消提取，未上传原片" : "素材导出失败："+error.localizedDescription
   }
   guard let self,self.generation==token else{return}
   self.worker=nil;self.working=false
  }
 }
 deinit {worker?.cancel()}
}
