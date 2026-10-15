import Foundation
import CoreGraphics
import Vision
import Libavformat
import Libavcodec
import Libavutil

/// Independent local demuxer: never requests the player's demand-generated HLS
/// segments, decodes movie frames, changes selected subtitles, or uploads audio.
enum FullFilmTranscriptReader {
 struct Output {let document:SubtitleDocument;let track:Int;let label:String;let duration:Double;let ocr:Bool}
 enum Failure:LocalizedError {
  case localOnly,noTrack,open,coordinate,inspect,decode,incomplete,tooLarge
  var errorDescription:String? {switch self {
   case .localOnly:return "完整内置字幕读取目前需要本机文件；可导入完整 SRT/ASS 字幕。"
   case .noTrack:return "影片没有可读取的内置字幕，可使用完整外置字幕。"
   case .open:return "已找到本机原片，但无法打开视频容器。请从“文件”App重新选择已下载完成的原片。"
   case .coordinate:return "“文件”App 暂未授权读取原片，请重新选择已完整下载的本地影片。"
   case .inspect:return "原片可打开，但字幕轨道信息读取失败。请重新选择原片再试。"
   case .decode:return "这个内置字幕轨道无法解码，可导入完整 SRT/ASS 字幕。"
   case .incomplete:return "字幕扫描未到文件结尾，不能标记全片读取完成。"
   case .tooLarge:return "字幕超出安全大小限制，未标记为全片完成。"
  }}
 }
 struct Track {let index:Int;let language:String;let title:String;let codec:AVCodecID}
 static func preferred(_ tracks:[Track],title:String?,language:String?=nil,streamIndex:Int?=nil)->Track? {
  if let streamIndex,let exact=tracks.first(where:{$0.index==streamIndex}) {return exact}
  if let language,!language.isEmpty {let code=language.lowercased().split(separator:"-").first.map(String.init) ?? language;let aliases=["zh":["chi","zho","zh"],"en":["eng","en"]];if let same=tracks.first(where:{(aliases[code] ?? [code]).contains($0.language.lowercased())}) {return same}}
  if let title,!title.isEmpty,let exact=tracks.first(where:{!$0.title.isEmpty && title.contains($0.title)}) {return exact}
  return tracks.first(where:{["zh","chi","zho"].contains($0.language.lowercased()) || $0.language.lowercased().hasPrefix("zh-")}) ?? tracks.first
 }
 static func extract(_ url:URL,preferredTitle:String?,preferredLanguage:String?=nil,preferredStreamIndex:Int?=nil,allowOCR:Bool,progress:(Double)->Void)throws->Output {
  guard url.isFileURL else{throw Failure.localOnly}
  // File Provider URLs can play through AVPlayer before their raw paths are
  // ready for FFmpeg. The coordinator grants access without copying the movie.
  let scope=url.startAccessingSecurityScopedResource()
  defer {if scope {url.stopAccessingSecurityScopedResource()}}
  let coordinator=NSFileCoordinator(filePresenter:nil)
  var coordinationError:NSError?
  var result:Result<Output,Error>?
  coordinator.coordinate(readingItemAt:url,options:.withoutChanges,error:&coordinationError) { accessibleURL in
   result=Result {
    try extractAccessibleMovie(accessibleURL,preferredTitle:preferredTitle,preferredLanguage:preferredLanguage,preferredStreamIndex:preferredStreamIndex,allowOCR:allowOCR,progress:progress)
   }
  }
  guard coordinationError==nil,let result else{throw Failure.coordinate}
  return try result.get()
 }
 private static func extractAccessibleMovie(_ url:URL,preferredTitle:String?,preferredLanguage:String?,preferredStreamIndex:Int?,allowOCR:Bool,progress:(Double)->Void)throws->Output {
  try Task.checkCancellation()
  var allocated:UnsafeMutablePointer<AVFormatContext>?
  guard avformat_open_input(&allocated,url.path,nil,nil)>=0,let format=allocated else{throw Failure.open}
  defer{avformat_close_input(&allocated)}
  let infoResult=avformat_find_stream_info(format,nil)
  // Unsupported video/audio decoders need not prevent a valid subtitle stream
  // from being enumerated from the local movie's container metadata.
  guard infoResult>=0 || format.pointee.nb_streams>0 else{throw Failure.inspect}
  let supported:[AVCodecID]=[AV_CODEC_ID_SUBRIP,AV_CODEC_ID_ASS,AV_CODEC_ID_SSA,AV_CODEC_ID_WEBVTT,AV_CODEC_ID_MOV_TEXT,AV_CODEC_ID_TEXT,AV_CODEC_ID_HDMV_PGS_SUBTITLE]
  var tracks:[Track]=[]
  for i in 0..<Int(format.pointee.nb_streams) {
   guard let stream=format.pointee.streams[i],let parameters=stream.pointee.codecpar,parameters.pointee.codec_type==AVMEDIA_TYPE_SUBTITLE,supported.contains(parameters.pointee.codec_id) else{continue}
   func metadata(_ name:String)->String {guard let entry=av_dict_get(stream.pointee.metadata,name,nil,0),let value=entry.pointee.value else{return ""};return String(cString:value)}
   tracks.append(Track(index:i,language:metadata("language"),title:metadata("title"),codec:parameters.pointee.codec_id))
  }
  guard let track=preferred(tracks,title:preferredTitle,language:preferredLanguage,streamIndex:preferredStreamIndex),let stream=format.pointee.streams[track.index] else{throw Failure.noTrack}
  let bitmap=track.codec==AV_CODEC_ID_HDMV_PGS_SUBTITLE
  guard !bitmap || allowOCR else{throw Failure.decode}
  guard let decoder=avcodec_find_decoder(track.codec),let context=avcodec_alloc_context3(decoder) else{
   #if DEBUG
   print("FullFilmTranscriptReader: missing subtitle decoder for \(track.codec)")
   #endif
   throw Failure.decode
  }
  var allocatedContext:UnsafeMutablePointer<AVCodecContext>?=context;defer{avcodec_free_context(&allocatedContext)}
  guard avcodec_parameters_to_context(context,stream.pointee.codecpar)>=0 else{throw Failure.decode}
  context.pointee.pkt_timebase=stream.pointee.time_base
  guard avcodec_open2(context,decoder,nil)>=0,let packet=av_packet_alloc() else{
   #if DEBUG
   print("FullFilmTranscriptReader: failed opening subtitle decoder")
   #endif
   throw Failure.decode
  }
  var allocatedPacket:UnsafeMutablePointer<AVPacket>?=packet;defer{av_packet_free(&allocatedPacket)}
  let videoIndex=av_find_best_stream(format,AVMEDIA_TYPE_VIDEO,-1,-1,nil,0)
  var origin=0.0
  if videoIndex>=0,let video=format.pointee.streams[Int(videoIndex)],video.pointee.start_time != Int64.min {origin=Double(video.pointee.start_time)*av_q2d(video.pointee.time_base)}
  let duration=format.pointee.duration>0 ? Double(format.pointee.duration)/Double(AV_TIME_BASE) : 0
  var cues:[SubtitleCue]=[];var bytes=0;var packets=0;var ended=false;var bitmapRects=0;var ocrMatches=0
  var pending:(start:Double,text:String)?
  var lastProgress = -1.0
  func append(_ text:String,start:Double,end:Double)throws {
   let clean=text.trimmingCharacters(in:.whitespacesAndNewlines)
   guard !clean.isEmpty,start.isFinite,end.isFinite,start>=0,end>start else{return}
   bytes+=clean.utf8.count
   guard bytes<=5*1024*1024,cues.count<30000 else{throw Failure.tooLarge}
   cues.append(SubtitleCue(start:start,end:end,text:clean))
  }
  while true {
   try Task.checkCancellation()
   let code=av_read_frame(format,packet)
   if code<0 {ended=code == -541478725;break} // AVERROR_EOF; other I/O errors are incomplete.
   defer{av_packet_unref(packet)}
   packets+=1
   // Yield disk/CPU time without blocking playback's own demux/decode queue.
   if packets%256==0 {Thread.sleep(forTimeInterval:0.002)}
   guard Int(packet.pointee.stream_index)==track.index else{continue}
   var subtitle=AVSubtitle();var got:Int32=0
   guard avcodec_decode_subtitle2(context,&subtitle,&got,packet)>=0 else{
    #if DEBUG
    print("FullFilmTranscriptReader: failed decoding PGS packet at \(packet.pointee.pts)")
    #endif
    throw Failure.decode
   }
   guard got != 0 else{continue};defer{avsubtitle_free(&subtitle)}
   let pts=subtitle.pts != Int64.min ? Double(subtitle.pts)/Double(AV_TIME_BASE) : Double(packet.pointee.pts)*av_q2d(stream.pointee.time_base)
   let start=pts+Double(subtitle.start_display_time)/1000-origin
   guard start.isFinite,start>=0 else{continue}
   let percent=duration>0 ? min(0.99,start/duration) : 0
   if percent-lastProgress>=0.02 {lastProgress=percent;progress(percent)}
   if bitmap,let prior=pending {try append(prior.text,start:prior.start,end:max(prior.start+0.01,start));pending=nil}
   var lines:[String]=[]
   for i in 0..<min(Int(subtitle.num_rects),32) {
    guard let pointer=subtitle.rects[i] else{continue};let rect=pointer.pointee
   if rect.type==SUBTITLE_BITMAP,bitmap {
    bitmapRects+=1
    if bitmapRects<=3 {
     #if DEBUG
     print("FullFilmTranscriptReader: rect w=\(rect.w) h=\(rect.h) stride=\(rect.linesize.0) colors=\(rect.nb_colors) data=\(rect.data.0 != nil && rect.data.1 != nil)")
     #endif
    }
    // A detached full-film scan has no run-loop boundary to drain the
    // autoreleased Vision/CG image buffers. Release every subtitle bitmap.
    let recognized=autoreleasepool {recognize(rect,language:track.language)}
    if let text=recognized {ocrMatches+=1;lines.append(text)}
    } else if let text=rect.text {lines.append(String(cString:text))}
    else if let ass=rect.ass {lines.append(cleanASS(String(cString:ass)))}
   }
   let text=lines.joined(separator:"\n")
   if bitmap {if !text.isEmpty {pending=(start,text)}}
   else {
    let subtitleDuration=Double(subtitle.end_display_time)/1000-Double(subtitle.start_display_time)/1000
    let packetDuration=Double(packet.pointee.duration)*av_q2d(stream.pointee.time_base)
    try append(text,start:start,end:start+max(0.01,subtitleDuration>0 && subtitleDuration<86400 ? subtitleDuration : packetDuration))
   }
  }
  guard ended else{throw Failure.incomplete}
  if let pending {try append(pending.text,start:pending.start,end:max(pending.start+0.01,min(pending.start+10,duration>0 ? duration : pending.start+10)))}
  #if DEBUG
  if bitmap {print("FullFilmTranscriptReader: PGS decoded OCR cues=\(cues.count), bytes=\(bytes), packets=\(packets)")}
  #endif
  guard let document=NativeSubtitleIndexReader.merge(cues),document.cues.count>=3 else{
   #if DEBUG
   print("FullFilmTranscriptReader: insufficient cues=\(cues.count) bitmapRects=\(bitmapRects) ocrMatches=\(ocrMatches) packets=\(packets)")
   #endif
   throw Failure.decode
  }
  progress(1)
  return Output(document:document,track:track.index,label:track.title.isEmpty ? track.language : track.title,duration:duration,ocr:bitmap)
 }
 static func cleanASS(_ value:String)->String {
  let parts=value.split(separator:",",maxSplits:8,omittingEmptySubsequences:false)
  let text=parts.count==9 ? String(parts[8]) : value
  return text.replacingOccurrences(of:"\\{[^}]*\\}",with:"",options:.regularExpression).replacingOccurrences(of:"\\N",with:"\n").replacingOccurrences(of:"\\n",with:"\n").replacingOccurrences(of:"\\h",with:" ")
 }
 private static func recognize(_ rect:AVSubtitleRect,language:String)->String? {
  guard rect.w>0,rect.h>0,Int(rect.w)<=4_194_304/Int(rect.h),rect.linesize.0>=rect.w,rect.nb_colors>0,rect.nb_colors<=256,let indices=rect.data.0,let palette=rect.data.1 else{return nil}
  let width=Int(rect.w),height=Int(rect.h),stride=Int(rect.linesize.0)
  var rgba=[UInt8](repeating:0,count:width*height*4)
  palette.withMemoryRebound(to:UInt32.self,capacity:Int(rect.nb_colors)) {colors in
   for y in 0..<height {for x in 0..<width {
    let index=Int(indices[y*stride+x]);guard index<Int(rect.nb_colors) else{continue}
    let argb=colors[index];let offset=(y*width+x)*4
    // Composite white subtitle glyphs onto opaque black for stable OCR.
    let alpha=Double((argb>>24)&255)/255
    rgba[offset]=UInt8(Double((argb>>16)&255)*alpha);rgba[offset+1]=UInt8(Double((argb>>8)&255)*alpha);rgba[offset+2]=UInt8(Double(argb&255)*alpha);rgba[offset+3]=255
   }}
  }
  guard let provider=CGDataProvider(data:Data(rgba) as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{return nil}
  let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=true
  request.preferBackgroundProcessing=true
  let supported=(try? request.supportedRecognitionLanguages()) ?? []
  let prefix=["chi":"zh","zho":"zh","eng":"en"].first(where:{$0.key==language})?.value ?? language
  if let match=supported.first(where:{$0.lowercased().hasPrefix(prefix.lowercased())}) {request.recognitionLanguages=[match]}
  // PGS subtitles can be very small in 480p and test media. Enlarge
  // tiny bitmaps for Vision without altering the playback subtitle track.
  let scale = height < 80 && width * height <= 250_000 ? 3 : 1
  var recognitionImage = image
  if scale > 1,let canvas=CGContext(data:nil,width:width*scale,height:height*scale,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
   canvas.interpolationQuality = .high
   canvas.draw(image,in:CGRect(x:0,y:0,width:width*scale,height:height*scale))
   recognitionImage = canvas.makeImage() ?? image
  }
  guard (try? VNImageRequestHandler(cgImage:recognitionImage).perform([request])) != nil else{return nil}
  let result=request.results?.sorted{$0.boundingBox.midY>$1.boundingBox.midY}.compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
  return result?.isEmpty == false ? result : nil
 }
}
