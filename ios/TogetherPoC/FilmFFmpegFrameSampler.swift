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
 private(set) var lastFailure:String?

 static func mediaDuration(_ url:URL)->Double? {
  guard url.isFileURL,!Task.isCancelled else{return nil}
  var pointer:UnsafeMutablePointer<AVFormatContext>?
  guard avformat_open_input(&pointer,url.path,nil,nil)>=0,let format=pointer else{return nil}
  defer{avformat_close_input(&pointer)}
  guard avformat_find_stream_info(format,nil)>=0 else{return nil}
  let value=Double(format.pointee.duration)/1_000_000
  return value.isFinite && value>0 ? value : nil
 }
 // Film subtitle extraction accepts usable container metadata even if the
 // optional full-stream probing of an exotic UHD video stream reports error.
 // Do not reject a real MKV video stream solely on that probe result.
 static func usableStreamMetadata(infoResult:Int32,streamCount:Int)->Bool {
  infoResult>=0 || streamCount>0
 }
 // Keep the provider's coordinated read scope for the lifetime of the
 // container open. The subtitle scanner already follows this pattern.
 // Once FFmpeg opens its own read-only FD, sampling never seeks the player.
 static func openCoordinated(url:URL,onFailure:@escaping (String)->Void={_ in})->FilmFFmpegFrameSampler? {
  guard url.isFileURL else {onFailure("只能读取本地电影");return nil}
  let coordinator=NSFileCoordinator(filePresenter:nil)
  var coordinationError:NSError?
  var sampler:FilmFFmpegFrameSampler?
  coordinator.coordinate(readingItemAt:url,options:.withoutChanges,error:&coordinationError) { accessible in
   sampler=FilmFFmpegFrameSampler(url:accessible,onFailure:onFailure)
  }
  if let coordinationError {
   onFailure("文件提供程序读取协调失败（错误码 \(coordinationError.code)）")
  }
  return sampler
 }
 init?(url:URL,onFailure:(String)->Void={_ in}) {
  guard url.isFileURL else{onFailure("容器打开失败：需要本地电影文件");return nil}
  var opened:UnsafeMutablePointer<AVFormatContext>?
  let openResult=avformat_open_input(&opened,url.path,nil,nil)
  guard openResult>=0,let source=opened else {
   if opened != nil {avformat_close_input(&opened)}
   onFailure("FFmpeg容器打开失败（错误码 \(openResult)）；请检查文件授权或文件提供程序是否已完成本地下载")
   return nil
  }
  let inspectResult=avformat_find_stream_info(source,nil)
  let streamCount=Int(source.pointee.nb_streams)
  guard Self.usableStreamMetadata(infoResult:inspectResult,streamCount:streamCount) else{
   onFailure("FFmpeg容器流信息读取失败（错误码 \(inspectResult)，轨道数\(streamCount)）")
   avformat_close_input(&opened);return nil
  }
  let preferred=av_find_best_stream(source,AVMEDIA_TYPE_VIDEO,-1,-1,nil,0)
  var streamIndex=preferred
  // If best-stream detection fails because of a nonessential stream or
  // unsupported codec, inspect actual video tracks without assuming AVPlayer
  // or subtitle probing have already prepared a decoder.
  var preferredUsable=false
  if preferred>=0,Int(preferred)<streamCount,
    let selected=source.pointee.streams[Int(preferred)],
    let props=selected.pointee.codecpar,
    props.pointee.codec_type==AVMEDIA_TYPE_VIDEO,
    avcodec_find_decoder(props.pointee.codec_id) != nil {
   preferredUsable=true
  }
  if !preferredUsable {
   streamIndex = -1
   for i in 0..<streamCount {
    guard let candidate=source.pointee.streams[i],
     let props=candidate.pointee.codecpar,
     props.pointee.codec_type==AVMEDIA_TYPE_VIDEO,
     avcodec_find_decoder(props.pointee.codec_id) != nil else{continue}
    streamIndex=Int32(i);break
   }
  }
  guard streamIndex>=0,Int(streamIndex)<streamCount,
   let stream=source.pointee.streams[Int(streamIndex)],
   let parameters=stream.pointee.codecpar else {
   var codes:[String]=[]
   for i in 0..<streamCount {
    if let stream=source.pointee.streams[i],let props=stream.pointee.codecpar,
      props.pointee.codec_type==AVMEDIA_TYPE_VIDEO {
     codes.append(String(props.pointee.codec_id.rawValue))
    }
   }
   onFailure(codes.isEmpty
    ? "MKV容器已打开，但没有识别到视频轨道（轨道数\(streamCount)，流检查错误码\(inspectResult)）"
    : "MKV已识别视频轨道，当前FFmpeg缺少该视频编码的解码器（codec ID \(codes.joined(separator:","))）")
   avformat_close_input(&opened);return nil
  }
  let codecName=String(parameters.pointee.codec_id.rawValue)
  guard let codec=avcodec_find_decoder(parameters.pointee.codec_id) else {
   onFailure("FFmpeg缺少codec ID \(codecName)视频解码器")
   avformat_close_input(&opened);return nil
  }
  guard let context=avcodec_alloc_context3(codec) else {
   onFailure("FFmpeg视频解码器分配失败（可能是内存不足，codec ID \(codecName)）")
   avformat_close_input(&opened);return nil
  }
  guard avcodec_parameters_to_context(context,parameters)>=0 else {
   onFailure("FFmpeg视频解码参数初始化失败（codec ID \(codecName)）")
   var d:UnsafeMutablePointer<AVCodecContext>?=context;avcodec_free_context(&d)
   avformat_close_input(&opened);return nil
  }
  // UHD reference surfaces are large; avoid extra frame-threading queues.
  context.pointee.thread_count=1
  context.pointee.thread_type=FF_THREAD_SLICE
  let openedCode=avcodec_open2(context,codec,nil)
  guard openedCode>=0 else {
   onFailure("FFmpeg视频解码器启动失败（codec ID \(codecName)，错误码\(openedCode)）")
   var d:UnsafeMutablePointer<AVCodecContext>?=context;avcodec_free_context(&d)
   avformat_close_input(&opened);return nil
  }
  guard let allocatedPacket=av_packet_alloc(),let allocatedFrame=av_frame_alloc() else {
   onFailure("FFmpeg抽帧内存分配失败")
   var d:UnsafeMutablePointer<AVCodecContext>?=context;avcodec_free_context(&d)
   avformat_close_input(&opened);return nil
  }
  let timebase=av_q2d(stream.pointee.time_base)
  guard timebase>0,timebase.isFinite else {
   onFailure("MKV视频时间基无效（codec ID \(codecName)）")
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
  lastDecodedTime=nil;lastFailure=nil
  guard !Task.isCancelled,seconds.isFinite,seconds>=0,
   let format,let decoder,let packet,let frame else {
   lastFailure="视频解码器尚未准备好或任务已取消";return nil
  }
  let target=firstTimestamp+Int64((seconds/secondsPerTick).rounded(.towardZero))
  // MKV files with sparse, late or absent cue indexes can reject a stream-
  // specific backward seek. Try the bounded libavformat alternatives before
  // giving up; never linear-scan a 20GB movie just to find one thumbnail.
  var seekCode=av_seek_frame(format,index,target,AVSEEK_FLAG_BACKWARD)
  if seekCode<0 {
   seekCode=avformat_seek_file(format,index,Int64.min,target,Int64.max,AVSEEK_FLAG_BACKWARD)
  }
  if seekCode<0 {
   let globalTarget=Int64((seconds*1_000_000).rounded(.towardZero))
   seekCode=av_seek_frame(format,-1,globalTarget,AVSEEK_FLAG_BACKWARD)
  }
  if seekCode<0 && seconds>0.5 {
   lastFailure="MKV 的视频索引不允许随机定位到 \(Int(seconds)) 秒";return nil
  }
  avcodec_flush_buffers(decoder)
  var packets=0,decoded=0,conversionFailures=0
  var nearby:(time:Double,image:CGImage)?
  var found:Double?
  let maxPackets=1800,maxFrames=640
  func acceptDecodedFrame() -> CGImage? {
   decoded+=1
   let pts=frame.pointee.best_effort_timestamp != Int64.min
    ? frame.pointee.best_effort_timestamp : frame.pointee.pts
   guard pts != Int64.min else{return nil}
   let position=Double(pts-firstTimestamp)*secondsPerTick
   guard position.isFinite,position>=0 else{return nil}
   found=position
   // A seek can land slightly before the target keyframe. Retain only one
   // genuine nearby image instead of rejecting every long-GOP 4K frame.
   let onTarget=position>=seconds-0.35 && position<=seconds+4
   let nearbyEarlier=position>=seconds-5 && position<seconds-0.35 &&
    (nearby.map{position-$0.time>0.9} ?? true)
   guard onTarget || nearbyEarlier else{return nil}
   guard let image=Self.convert(frame) else{conversionFailures+=1;return nil}
   if onTarget {lastDecodedTime=position;return image}
   nearby=(position,image)
   return nil
  }
  while packets<maxPackets && decoded<maxFrames {
   if Task.isCancelled {lastFailure="已取消抽帧";return nil}
   let status=av_read_frame(format,packet)
   if status<0 {break}
   defer {av_packet_unref(packet)}
   packets+=1
   guard packet.pointee.stream_index==index else{continue}
   let sent=avcodec_send_packet(decoder,packet)
   if sent<0 {continue}
   while avcodec_receive_frame(decoder,frame)>=0 {
    let image=acceptDecodedFrame()
    av_frame_unref(frame)
    if let image {return image}
    if decoded>=maxFrames {break}
   }
  }
  // Drain decoder delay frames for short fixtures and the end of a GOP.
  if !Task.isCancelled && avcodec_send_packet(decoder,nil)>=0 {
   var drained=0
   while drained<maxFrames-decoded && avcodec_receive_frame(decoder,frame)>=0 {
    drained+=1
    let image=acceptDecodedFrame()
    av_frame_unref(frame)
    if let image {return image}
   }
  }
  if let nearby {lastDecodedTime=nearby.time;return nearby.image}
  if conversionFailures>0 {
   lastFailure="已解码视频帧，但像素格式或HDR画面转换失败（\(conversionFailures)次）"
  } else if decoded==0 {
   lastFailure="视频定位后未解码出画面（已读取\(packets)个数据包）"
  } else {
   lastFailure="已解码\(decoded)帧，最后时间\(Int(found ?? 0))秒，仍未取得\(Int(seconds))秒附近画面"
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
