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
 private(set) var lastDecodedTime:Double?

 static func mediaDuration(_ url:URL)->Double? {
  guard url.isFileURL,!Task.isCancelled else{return nil}
  var pointer:UnsafeMutablePointer<AVFormatContext>?
  guard avformat_open_input(&pointer,url.path,nil,nil)>=0,let format=pointer else{return nil}
  defer{avformat_close_input(&pointer)}
  guard avformat_find_stream_info(format,nil)>=0 else{return nil}
  let value=Double(format.pointee.duration)/1_000_000
  return value.isFinite && value>0 ? value : nil
 }
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
  // Tiny fixtures and short GOPs can retain their only picture until EOF;
  // select a bounded worker count BEFORE opening the decoder.
  guard avcodec_parameters_to_context(context,parameters)>=0 else {
   var d:UnsafeMutablePointer<AVCodecContext>?=context;avcodec_free_context(&d)
   avformat_close_input(&opened);return nil
  }
  context.pointee.thread_count=2
  guard avcodec_open2(context,codec,nil)>=0,
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
 }
 deinit {
  if packet != nil {av_packet_free(&packet)}
  if frame != nil {av_frame_free(&frame)}
  if decoder != nil {avcodec_free_context(&decoder)}
  if format != nil {avformat_close_input(&format)}
 }
 func image(at seconds:Double)->CGImage? {
  lastDecodedTime=nil
  guard !Task.isCancelled,seconds.isFinite,seconds>=0,let format,let decoder,let packet,let frame else{return nil}
  let target=firstTimestamp+Int64((seconds/secondsPerTick).rounded(.towardZero))
  // Some one-frame MP4 fixtures do not carry a seek index. At time zero
  // the demuxer is already positioned correctly, so decoding can continue.
  let seekResult=av_seek_frame(format,index,target,AVSEEK_FLAG_BACKWARD)
  if seekResult<0 && seconds>0.5 {return nil}
  avcodec_flush_buffers(decoder)
  var visited=0,decoded=0
  while visited<900,decoded<380 {
   if Task.isCancelled {return nil}
   visited+=1
   guard av_read_frame(format,packet)>=0 else{break}
   defer {av_packet_unref(packet)}
   guard packet.pointee.stream_index==index, avcodec_send_packet(decoder,packet)>=0 else{continue}
   while avcodec_receive_frame(decoder,frame)>=0 {
    decoded+=1
    let stamp=frame.pointee.best_effort_timestamp
    let position=stamp==Int64.min ? -1 : Double(stamp-firstTimestamp)*secondsPerTick
    if position>=seconds-0.35,let converted=Self.convert(frame) {
     lastDecodedTime=position;av_frame_unref(frame);return converted
    }
    av_frame_unref(frame)
    if decoded>=380 {break}
   }
  }
  // B-frames and decoders with frame threading may return the final picture
  // only after avcodec_send_packet(nil) signals end-of-stream.
  if avcodec_send_packet(decoder,nil)>=0 {
   while avcodec_receive_frame(decoder,frame)>=0 {
    let stamp=frame.pointee.best_effort_timestamp
    let position=stamp==Int64.min ? -1 : Double(stamp-firstTimestamp)*secondsPerTick
    if (position>=seconds-0.35 || (seconds<=0.5 && stamp==Int64.min)),
      let converted=Self.convert(frame) {
     lastDecodedTime=position;av_frame_unref(frame);return converted
    }
    av_frame_unref(frame)
   }
  }
  return nil
 }
 private static func convert(_ frame:UnsafeMutablePointer<AVFrame>)->CGImage? {
  let w=Int(frame.pointee.width),h=Int(frame.pointee.height)
  guard w>=16,h>=16,w<=8192,h<=8192,frame.pointee.format>=0 else{return nil}
  let inputFormat=AVPixelFormat(rawValue:frame.pointee.format)
  let scale=min(480.0/Double(w),270.0/Double(h),1.0)
  let outputW=max(1,Int(Double(w)*scale)),outputH=max(1,Int(Double(h)*scale))
  guard let scaler=sws_getContext(Int32(w),Int32(h),inputFormat,
   Int32(outputW),Int32(outputH),AV_PIX_FMT_BGRA,Int32(SWS_BILINEAR.rawValue),nil,nil,nil) else{return nil}
  defer{sws_freeContext(scaler)}
  // FFmpeg coefficient IDs: 9=BT.2020, 1=BT.709, 5=BT.601.
  let colors=frame.pointee.colorspace.rawValue
  let coefficient:Int32=(colors==9 || colors==10) ? 9 : (colors==1 ? 1 : 5)
  if let table=sws_getCoefficients(coefficient) {
   _=sws_setColorspaceDetails(scaler,table,frame.pointee.color_range.rawValue==2 ? 1 : 0,table,1,0,1<<16,1<<16)
  }
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
  guard rows==Int32(outputH) else{return nil}
  let transfer=frame.pointee.color_trc.rawValue
  // 16=PQ (ST2084), 18=HLG. Swscale performs YUV conversion but not HDR
  // tone mapping. Apply an explicit SDR transform at thumbnail resolution.
  if transfer==16 || transfer==18 {
   FilmHDRToneMap.apply(&imageBytes,pq:transfer==16,bt2020:colors==9 || colors==10)
  }
  guard let provider=CGDataProvider(data:imageBytes as CFData) else{return nil}
  let bitmap=CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
  return CGImage(width:outputW,height:outputH,bitsPerComponent:8,bitsPerPixel:32,
   bytesPerRow:bytesPerRow,space:CGColorSpaceCreateDeviceRGB(),
   bitmapInfo:bitmap,provider:provider,decode:nil,
   shouldInterpolate:true,intent:.defaultIntent)
 }
}

// Bounded thumbnail transform; never applied to the actual playback surface.
enum FilmHDRToneMap {
 static func apply(_ bytes:inout Data,pq:Bool,bt2020:Bool) {
  let linear=(0..<256).map{index -> Double in
   let v=Double(index)/255
   if pq {
    let p=pow(v,1/(2523.0/32)),n=max(p-3424.0/4096,0),d=max(2413.0/128-2392.0/128*p,0.000001)
    return 100*pow(n/d,1/(2610.0/16384)) // units of SDR 100 nits
   }
   let a=0.17883277,b=0.28466892,c=0.55991073
   return (v<=0.5 ? v*v/3 : (exp((v-c)/a)+b)/12)*10
  }
  func encode(_ value:Double)->UInt8 {
   let x=max(0,min(1,value)),s=x<=0.0031308 ? x*12.92 : 1.055*pow(x,1/2.4)-0.055
   return UInt8(max(0,min(255,(s*255).rounded())))
  }
  bytes.withUnsafeMutableBytes{(raw:UnsafeMutableRawBufferPointer) in
   let p=raw.bindMemory(to:UInt8.self)
   for i in stride(from:0,to:max(0,p.count-3),by:4) {
    var r=linear[Int(p[i+2])],g=linear[Int(p[i+1])],b=linear[Int(p[i])]
    if bt2020 {
     let rr=1.6605*r-0.5876*g-0.0728*b,gg = -0.1246*r+1.1329*g-0.0083*b,bb = -0.0182*r-0.1006*g+1.1187*b
     r=max(0,rr);g=max(0,gg);b=max(0,bb)
    }
    let l=0.2126*r+0.7152*g+0.0722*b
    let mapped=l/(1+l),scale=l>0.000001 ? mapped/l : 0
    p[i]=encode(b*scale);p[i+1]=encode(g*scale);p[i+2]=encode(r*scale);p[i+3]=255
   }
  }
 }
}
