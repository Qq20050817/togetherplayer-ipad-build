import Foundation
import Libavformat
import Libavcodec
import Libavutil

/// Safely extracts *original* palettized PGS subtitle compositions from a
/// local, file-backed MKV. It does not transcode the movie or call Vision OCR.
/// This first adapter intentionally declines remote HTTP, DRM and SMB streams:
/// scanning the film a second time over the network would harm playback.
enum OriginalPGSFileExtractor {
 enum Failure:Error {case unsupportedSource,openFailed,missingTrack,codecFailed,readFailed}
 static let maximumInputBytes:Int64 = 256*1024*1024
 static let maximumEvents=1000

 /// Run on a background thread. FFmpeg demuxing is synchronous.
 static func extract(url:URL,streamIndex:Int)->[PGSBitmapEvent] {
  guard url.isFileURL,streamIndex>=0 else{return []}
  let scoped=url.startAccessingSecurityScopedResource()
  defer {if scoped {url.stopAccessingSecurityScopedResource()}}
  var format:UnsafeMutablePointer<AVFormatContext>?
  guard avformat_open_input(&format,url.path,nil,nil)>=0,let format else{return []}
  defer {
   var source:UnsafeMutablePointer<AVFormatContext>?=format
   avformat_close_input(&source)
  }
  guard avformat_find_stream_info(format,nil)>=0,
   Int(format.pointee.nb_streams)>streamIndex,
   let source=format.pointee.streams[streamIndex] else{return []}
  let parameters=source.pointee.codecpar
  guard parameters?.pointee.codec_id==AV_CODEC_ID_HDMV_PGS_SUBTITLE,
   let codec=avcodec_find_decoder(AV_CODEC_ID_HDMV_PGS_SUBTITLE),
   let context=avcodec_alloc_context3(codec) else{return []}
  var decoding:UnsafeMutablePointer<AVCodecContext>?=context
  defer {avcodec_free_context(&decoding)}
  guard avcodec_parameters_to_context(context,parameters)>=0 else{return []}
  context.pointee.pkt_timebase=source.pointee.time_base
  guard avcodec_open2(context,codec,nil)>=0 else{return []}
  guard let packet=av_packet_alloc() else{return []}
  var allocated:UnsafeMutablePointer<AVPacket>?=packet
  defer {av_packet_free(&allocated)}
  var output:[PGSBitmapEvent]=[]
  var inputBytes:Int64=0
  let videoIndex=av_find_best_stream(format,AVMEDIA_TYPE_VIDEO,-1,-1,nil,0)
  var origin=0.0
  if videoIndex>=0,
     let video=format.pointee.streams[Int(videoIndex)],
     video.pointee.start_time != swift_AV_NOPTS_VALUE() {
   origin=Double(video.pointee.start_time)*av_q2d(video.pointee.time_base)
  }
  while output.count<maximumEvents, inputBytes<maximumInputBytes {
   let result=av_read_frame(format,packet)
   guard result>=0 else{break}
   defer {av_packet_unref(packet)}
   inputBytes+=Int64(max(0,packet.pointee.size))
   guard Int(packet.pointee.stream_index)==streamIndex else{continue}
   var subtitle=AVSubtitle()
   var got:Int32=0
   let decoded=avcodec_decode_subtitle2(context,&subtitle,&got,packet)
   guard decoded>=0,got != 0 else{continue}
   defer {avsubtitle_free(&subtitle)}
   let pts:Double
   if subtitle.pts != swift_AV_NOPTS_VALUE() {
    pts=Double(subtitle.pts)/Double(AV_TIME_BASE)
   } else if packet.pointee.pts != swift_AV_NOPTS_VALUE() {
    pts=Double(packet.pointee.pts)*av_q2d(source.pointee.time_base)
   } else {continue}
   let t=pts+Double(subtitle.start_display_time)/1000-origin
   guard t.isFinite,t>=0 else{continue}
   if subtitle.num_rects == 0 {
    output.append(PGSBitmapEvent(time:t,frame:nil));continue
   }
   let width=Int(parameters!.pointee.width)
   let height=Int(parameters!.pointee.height)
   guard width>0,height>0,width<=16384,height<=16384 else{continue}
   var objects:[PGSBitmapObject]=[]
   for i in 0..<min(Int(subtitle.num_rects),PGSBitmapComposition.maxObjects) {
    guard let pointer=subtitle.rects[i] else{continue}
    let rect=pointer.pointee
    guard rect.type == SUBTITLE_BITMAP,
      rect.w>0,rect.h>0,rect.h<=PGSBitmapComposition.maxPixelsPerObject,
      rect.w<=PGSBitmapComposition.maxPixelsPerObject/rect.h,
      rect.nb_colors>0,rect.nb_colors<=256,
      rect.linesize.0>=rect.w,
      let indices=rect.data.0,let palette=rect.data.1 else{continue}
    let w=Int(rect.w),h=Int(rect.h),stride=Int(rect.linesize.0)
    var pixels=[UInt8](repeating:0,count:w*h)
    for y in 0..<h {
     for x in 0..<w {pixels[y*w+x]=indices[y*stride+x]}
    }
    let colors=palette.withMemoryRebound(to:UInt32.self,capacity:Int(rect.nb_colors)) {
     Array(UnsafeBufferPointer(start:$0,count:Int(rect.nb_colors)))
    }
    objects.append(PGSBitmapObject(x:Int(rect.x),y:Int(rect.y),width:w,height:h,
                                    indices:pixels,paletteARGB:colors))
   }
   if !objects.isEmpty {
    output.append(PGSBitmapEvent(time:t,
     frame:PGSBitmapFrame(videoWidth:width,videoHeight:height,objects:objects)))
   }
  }
  return output
 }
}
