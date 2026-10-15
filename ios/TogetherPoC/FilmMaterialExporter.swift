import Foundation
import AVFoundation
import UIKit
import CryptoKit

// Offline, explicitly initiated export. No film, frames or subtitles are
// automatically transmitted to a server or to an AI provider.
enum FilmMaterialExportFailure:LocalizedError {
 case localFileRequired,missingSubtitles,framesUnavailable,missingDuration,tooManyFiles
 var errorDescription:String? {switch self {
  case .localFileRequired:return "请先在 iPad“文件”中选择可读取的本地原片；网盘在线播放链接不支持直接导出原始画面。"
  case .missingSubtitles:return "未读取到完整字幕。可以先导入 SRT/ASS 字幕，再导出素材。"
  case .framesUnavailable:return "原片可读取字幕，但独立抽帧失败，未导出只有字幕的假完整素材。请使用可本地解码的影片文件。"
  case .missingDuration:return "无法确定影片时长，请确认原片完整。"
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
}

enum FilmMaterialFingerprint {
 static func source(_ url:URL)throws->String {
  let handle=try FileHandle(forReadingFrom:url)
  defer {try? handle.close()}
  let size=try handle.seekToEnd()
  guard size>0 else{throw FilmMaterialExportFailure.localFileRequired}
  try handle.seek(toOffset:0)
  let first=try handle.read(upToCount:65_536) ?? Data()
  try handle.seek(toOffset:size>65_536 ? size-65_536 : 0)
  let last=try handle.read(upToCount:65_536) ?? Data()
  var sha=SHA256()
  sha.update(data:Data(String(size).utf8));sha.update(data:first);sha.update(data:last)
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
   u32(0x04034b50,into:&result);u16(20,into:&result);u16(0,into:&result);u16(0,into:&result)
   u16(0,into:&result);u16(0,into:&result);u32(checksum,into:&result);u32(size,into:&result);u32(size,into:&result)
   u16(UInt16(name.count),into:&result);u16(0,into:&result);result.append(name);result.append(data)
   u32(0x02014b50,into:&central);u16(20,into:&central);u16(20,into:&central)
   u16(0,into:&central);u16(0,into:&central);u16(0,into:&central);u16(0,into:&central)
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
  let additions=gaps.sorted{$0.1>$1.1}.prefix(30).map{$0.0}
  var selected:[Double]=[]
  for t in (baseline+additions).sorted() {
   if t>=0,t<duration,selected.last.map({t-$0>=7}) ?? true {selected.append(t)}
  }
  return Array(selected.prefix(180))
 }
 private static func contactSheet(_ frames:[(Double,CGImage)])->Data? {
  guard !frames.isEmpty else{return nil}
  let columns=4,cellW=250,cellH=165
  let rows=(frames.count+columns-1)/columns
  let renderer=UIGraphicsImageRenderer(size:CGSize(width:columns*cellW,height:rows*cellH))
  let image=renderer.image { context in
   UIColor.black.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:columns*cellW,height:rows*cellH))
   for (index,value) in frames.enumerated() {
    let x=(index%columns)*cellW,y=(index/columns)*cellH
    let image=UIImage(cgImage:value.1)
    image.draw(in:CGRect(x:x,y:y,width:cellW,height:cellH-25))
    let seconds=Int(value.0.rounded())
    let timestamp=String(format:"%02d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60)
    let text=timestamp as NSString
    text.draw(at:CGPoint(x:x+8,y:y+cellH-23),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:15,weight:.semibold),.foregroundColor:UIColor.white])
   }
  }
  return image.jpegData(compressionQuality:0.76)
 }
 static func create(url:URL,title:String,external:SubtitleDocument?,allowOCR:Bool,progress:@escaping (Double)->Void)throws->URL {
  guard url.isFileURL else{throw FilmMaterialExportFailure.localFileRequired}
  let scoped=url.startAccessingSecurityScopedResource()
  defer {if scoped {url.stopAccessingSecurityScopedResource()}}
  guard FileManager.default.isReadableFile(atPath:url.path) else{throw FilmMaterialExportFailure.localFileRequired}
  let fingerprint=try FilmMaterialFingerprint.source(url)
  let extracted:FullFilmTranscriptReader.Output?
  if external != nil {extracted=nil}
  else {extracted=try FullFilmTranscriptReader.extract(url,preferredTitle:nil,allowOCR:allowOCR,progress:{value in progress(value*0.25)})}
  guard let subtitles=external ?? extracted?.document else{throw FilmMaterialExportFailure.missingSubtitles}
  let srt=SubtitleSRTEncoder.encode(subtitles)
  guard !srt.isEmpty else{throw FilmMaterialExportFailure.missingSubtitles}
  let asset=AVURLAsset(url:url)
  let assetDuration=asset.duration.seconds
  let duration=extracted?.duration ?? (assetDuration.isFinite ? assetDuration : subtitles.cues.last?.end ?? 0)
  guard duration.isFinite,duration>=60,duration<=43_200 else{throw FilmMaterialExportFailure.missingDuration}
  let times=selectedTimes(duration:duration,subtitles:subtitles)
  let generator=AVAssetImageGenerator(asset:asset)
  generator.appliesPreferredTrackTransform=true
  generator.maximumSize=CGSize(width:500,height:300)
  generator.requestedTimeToleranceBefore=CMTime(seconds:1,preferredTimescale:600)
  generator.requestedTimeToleranceAfter=CMTime(seconds:1,preferredTimescale:600)
  var sheets:[(String,Data)]=[]
  var pending:[(Double,CGImage)]=[]
  var frameTimes:[Int]=[]
  // AVAssetImageGenerator cannot decode many MKV/HEVC containers directly.
  // Use the already-shipped FFmpeg libraries for local, independent decoding.
  let directFFmpeg=["mkv","webm","ts","m2ts","avi"].contains(url.pathExtension.lowercased())
  var ffmpeg:FilmFFmpegFrameSampler?=directFFmpeg ? FilmFFmpegFrameSampler(url:url) : nil
  for (index,time) in times.enumerated() {
   try Task.checkCancellation()
   var frame:CGImage?
   if directFFmpeg {frame=ffmpeg?.image(at:time)}
   else {
    frame=try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:nil)
    if frame==nil {
     if ffmpeg==nil {ffmpeg=FilmFFmpegFrameSampler(url:url)}
     frame=ffmpeg?.image(at:time)
    }
   }
   if let image=frame {
    pending.append((time,image));frameTimes.append(Int((time*1000).rounded()))
    if pending.count==16,let bytes=contactSheet(pending) {
     sheets.append((String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1),bytes));pending=[]
    }
   }
   if index%5==0 {progress(0.25+0.70*Double(index+1)/Double(max(1,times.count)))}
  }
  if !pending.isEmpty,let bytes=contactSheet(pending) {sheets.append((String(format:"contact-sheets/scene-%03d.jpg",sheets.count+1),bytes))}
  // We cannot claim to have understood the film's images if sampling failed.
  guard frameTimes.count>=min(4,times.count),
   Double(frameTimes.count)>=Double(times.count)*0.25 else{throw FilmMaterialExportFailure.framesUnavailable}
  let manifest=FilmMaterialManifest(schemaVersion:1,title:String(title.prefix(180)),durationMs:Int((duration*1000).rounded()),sourceFingerprint:fingerprint,subtitleFingerprint:FilmMaterialFingerprint.subtitles(srt),subtitleCueCount:subtitles.cues.count,frameCount:frameTimes.count,contactSheets:sheets.map{$0.0},frameTimesMs:frameTimes,frameExportMode:"AVFoundation/FFmpeg sampled frames; dialogue gaps supplemented; missing motion between still frames is not inferred")
  let enc=JSONEncoder();enc.outputFormatting=[.prettyPrinted,.sortedKeys]
  let info=try enc.encode(manifest)
  let instructions="TogetherPlayer 电影素材包 v1\n本包含完整时间轴字幕、按时间顺序的多张分镜图以及严格对应的时间信息。\n请用 ChatGPT 项目指令制作 AI 题库。每道题提供已观看证据、未来揭晓依据、触发时间和安全答案揭晓时间。\n图片是离散截图，无法证明缺失画面之间的连续动作。不要编造未覆盖的视觉情节。\n生成 JSON 时 schemaVersion=1，影片 durationMs、sourceFingerprint、subtitleFingerprint 必须从 manifest.json 原样复制。\n题库还需通过 App 的校验再运行。\n"
  var entries:[(String,Data)]=[("manifest.json",info),("subtitles/whole-film.srt",Data(srt.utf8)),("README.txt",Data(instructions.utf8))]
  entries.append(contentsOf:sheets)
  guard let archive=FilmMaterialZip.make(entries) else{throw FilmMaterialExportFailure.tooManyFiles}
  let document=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("AI素材",isDirectory:true)
  try FileManager.default.createDirectory(at:document,withIntermediateDirectories:true)
  let name=url.deletingPathExtension().lastPathComponent
   .replacingOccurrences(of:"[^a-zA-Z0-9_\\-一-龥]",with:"_",options:.regularExpression)
  let filename=String(name.prefix(52))
  let output=document.appendingPathComponent(filename+"-"+String(fingerprint.prefix(12))+".zip")
  try archive.write(to:output,options:.atomic)
  progress(1)
  return output
 }
}

@MainActor final class FilmMaterialExportSession:ObservableObject {
 @Published private(set) var working=false
 @Published private(set) var progress=0.0
 @Published private(set) var status="请先加载本地原片"
 @Published private(set) var file:URL?
 func begin(url:URL?,title:String,external:SubtitleDocument?,allowOCR:Bool) {
  guard !working else{return}
  guard let url,url.isFileURL else{status=FilmMaterialExportFailure.localFileRequired.localizedDescription;return}
  working=true;progress=0;file=nil;status="正在导出字幕和关键画面…"
  Task {
   do {
    let output=try await Task.detached(priority:.utility) {
     try FilmMaterialExporter.create(url:url,title:title,external:external,allowOCR:allowOCR,progress:{value in
      Task {@MainActor in self.progress=value}
     })
    }.value
    file=output;status="素材包已就绪，点击“分享给 ChatGPT”或在“文件”中查找。"
   } catch {status="素材导出失败："+error.localizedDescription}
   working=false
  }
 }
}
