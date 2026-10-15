import Foundation
import CoreGraphics
import Libavformat
import Libavcodec
import Libavutil
import Libswscale

// Read-only, separate FFmpeg decoder for locally accessible MKV/HEVC movies.
// This never seeks the live AVPlayer, touches the room clock or starts a server.
final class FilmFFmpegFrameSampler {
 private var format:UnsafeMutablePointer<AVFormatContext>?
 private var decoder:UnsafeMutablePointer<AVCodecContext>?
 private var packet:UnsafeMutablePointer<AVPacket>?
 private var frame:UnsafeMutablePointer<AVFrame>?
 private let index:Int32
 private let secondsPerTick:Double
 private let firstTimestamp:Int64

 init?(url:URL) {
  guard url.isFileURL else{return nil}
  var opened:UnsafeMutablePointer<AVFormatContext>?
  guard avformat_open_input(&opened,url.path,nil,nil)>=0,let source=opened else{return nil}
  guard avformat_find_stream_info(source,nil)>=0 else {
   avformat_close_input(&opened);return nil
  }
  let streamIndex=av_find_best_stream(source,AVMEDIA_TYPE_VIDEO,-1,-1,nil,0)
  guard streamIndex>=0,let stream=source.pointee.streams[Int(streamIndex)],
   let parameters=stream.pointee.codecpar,
   let codec=avcodec_find_decoder(parameters.pointee.codec_id),
   let context=avcodec_alloc_context3(codec) else {
   avformat_close_input(&opened);return nil
  }
  guard avcodec_parameters_to_context(context,parameters)>=0,
   avcodec_open2(context,codec,nil)>=0,
   let allocatedPacket=av_packet_alloc(),let allocatedFrame=av_frame_alloc() else {
   var d:UnsafeMutablePointer<AVCodecContext>?=context;avcodec_free_context(&d)
   avformat_close_input(&opened);return nil
  }
  let timebase=av_q2d(stream.pointee.time_base)
  guard timebase>0,timebase.isFinite else {
   var p:UnsafeMutablePointer<AVPacket>?=allocatedPacket
   var f:UnsafeMutablePointer<AVFrame>?=allocatedFrame
   var d:UnsafeMutablePointer<AVCodecContext>?=context
   av_packet_free(&p);av_frame_free(&f);avcodec_free_context(&d)
   avformat_close_input(&opened);return nil
  }
  self.format=opened;self.decoder=context;self.packet=allocatedPacket;self.frame=allocatedFrame
  self.index=streamIndex;self.secondsPerTick=timebase
  self.firstTimestamp=stream.pointee.start_time==Int64.min ? 0 : stream.pointee.start_time
  context.pointee.thread_count=2
 }
 deinit {
  if packet != nil {av_packet_free(&packet)}
  if frame != nil {av_frame_free(&frame)}
  if decoder != nil {avcodec_free_context(&decoder)}
  if format != nil {avformat_close_input(&format)}
 }
 func image(at seconds:Double)->CGImage? {
  guard seconds.isFinite,seconds>=0,let format,let decoder,let packet,let frame else{return nil}
  let target=firstTimestamp+Int64((seconds/secondsPerTick).rounded(.towardZero))
  guard av_seek_frame(format,index,target,AVSEEK_FLAG_BACKWARD)>=0 else{return nil}
  avcodec_flush_buffers(decoder)
  var visited=0,decoded=0
  while visited<900,decoded<380 {
   visited+=1
   guard av_read_frame(format,packet)>=0 else{break}
   defer {av_packet_unref(packet)}
   guard packet.pointee.stream_index==index, avcodec_send_packet(decoder,packet)>=0 else{continue}
   while avcodec_receive_frame(decoder,frame)>=0 {
    decoded+=1
    let stamp=frame.pointee.best_effort_timestamp
    let position=stamp==Int64.min ? -1 : Double(stamp-firstTimestamp)*secondsPerTick
    if position>=seconds-0.35,let converted=Self.convert(frame) {
     av_frame_unref(frame);return converted
    }
    av_frame_unref(frame)
    if decoded>=380 {break}
   }
  }
  return nil
 }
 private static func convert(_ frame:UnsafeMutablePointer<AVFrame>)->CGImage? {
  let w=Int(frame.pointee.width),h=Int(frame.pointee.height)
  guard w>=16,h>=16,w<=8192,h<=8192,frame.pointee.format>=0 else{return nil}
  let inputFormat=AVPixelFormat(rawValue:frame.pointee.format)
  let outputW=min(480,w)
  let outputH=max(1,min(270,Int((Double(outputW)*Double(h)/Double(w)).rounded())))
  guard let scaler=sws_getContext(Int32(w),Int32(h),inputFormat,
   Int32(outputW),Int32(outputH),AV_PIX_FMT_BGRA,Int32(SWS_BILINEAR.rawValue),nil,nil,nil) else{return nil}
  defer{sws_freeContext(scaler)}
  let bytesPerRow=outputW*4
  var imageBytes=Data(count:bytesPerRow*outputH)
  let sourcePlanes:[UnsafePointer<UInt8>?]=[
   frame.pointee.data.0.map{UnsafePointer($0)},
   frame.pointee.data.1.map{UnsafePointer($0)},
   frame.pointee.data.2.map{UnsafePointer($0)},
   frame.pointee.data.3.map{UnsafePointer($0)}
  ]
  let sourceStrides:[Int32]=[
   frame.pointee.linesize.0,frame.pointee.linesize.1,
   frame.pointee.linesize.2,frame.pointee.linesize.3
  ]
  let rows=imageBytes.withUnsafeMutableBytes{outputRaw -> Int32 in
   guard let first=outputRaw.baseAddress?.assumingMemoryBound(to:UInt8.self) else{return 0}
   var destinations:[UnsafeMutablePointer<UInt8>?]=[first,nil,nil,nil]
   var outputStrides:[Int32]=[Int32(bytesPerRow),0,0,0]
   return sourcePlanes.withUnsafeBufferPointer{source in
    sourceStrides.withUnsafeBufferPointer{sourceStride in
     destinations.withUnsafeMutableBufferPointer{destination in
      outputStrides.withUnsafeMutableBufferPointer{destinationStride in
       sws_scale(scaler,source.baseAddress,sourceStride.baseAddress,0,Int32(h),
        destination.baseAddress,destinationStride.baseAddress)
      }
     }
    }
   }
  }
  guard rows==Int32(outputH),let provider=CGDataProvider(data:imageBytes as CFData) else{return nil}
  let bitmap=CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
  return CGImage(width:outputW,height:outputH,bitsPerComponent:8,bitsPerPixel:32,
   bytesPerRow:bytesPerRow,space:CGColorSpaceCreateDeviceRGB(),
   bitmapInfo:bitmap,provider:provider,decode:nil,
   shouldInterpolate:true,intent:.defaultIntent)
 }
}
