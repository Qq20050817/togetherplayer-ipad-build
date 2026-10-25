import Foundation
import Libavformat
import Libavcodec
import Libavutil
import Libswresample

enum FilmAudioSampleError: LocalizedError {
 case opening, missingTrack, decoder, seek, insufficientAudio, cancelled
 var errorDescription: String? {
  switch self {
  case .opening: return "无法读取原片。请检查 U 盘 HTTP Range 或本地文件权限。"
  case .missingTrack: return "原片没有可解码的音轨。"
  case .decoder: return "原片音频解码失败或音频格式不受支持。"
  case .seek: return "原片索引不支持在指定位置随机读取音轨。"
  case .insufficientAudio: return "采样区域内没有足够的有效音频，字幕保持不变。"
  case .cancelled: return "字幕校验已取消。"
  }
 }
}

/// Read-only libavformat sampler. Call on a background task; it never seeks
/// the live player, downloads a complete movie or writes a local audio file.
final class FilmFFmpegAudioSampler {
 struct Clip {
  let pcm16le: Data
  let actualStartSeconds: Double
  let sampleRate = 16_000
  let channels = 1
 }
 private var format: UnsafeMutablePointer<AVFormatContext>?
 private var decoder: UnsafeMutablePointer<AVCodecContext>?
 private var packet: UnsafeMutablePointer<AVPacket>?
 private var frame: UnsafeMutablePointer<AVFrame>?
 private let streamIndex: Int32
 private let secondsPerTick: Double
 private var resampler: UnsafeMutablePointer<SwrContext>?

 init(url: URL) throws {
  guard url.isFileURL || ["http","https"].contains(url.scheme?.lowercased() ?? "") else {
   throw FilmAudioSampleError.opening
  }
  var opened: UnsafeMutablePointer<AVFormatContext>?
  guard avformat_open_input(&opened,url.isFileURL ? url.path : url.absoluteString,nil,nil)>=0,
   let opened else { throw FilmAudioSampleError.opening }
  format=opened
  _ = avformat_find_stream_info(opened,nil)
  let chosen=av_find_best_stream(opened,AVMEDIA_TYPE_AUDIO,-1,-1,nil,0)
  guard chosen>=0,Int(chosen)<Int(opened.pointee.nb_streams),
   let stream=opened.pointee.streams[Int(chosen)],
   let params=stream.pointee.codecpar,
   let codec=avcodec_find_decoder(params.pointee.codec_id) else { throw FilmAudioSampleError.missingTrack }
  guard let context=avcodec_alloc_context3(codec) else { throw FilmAudioSampleError.decoder }
  decoder=context
  guard avcodec_parameters_to_context(context,params)>=0 else { throw FilmAudioSampleError.decoder }
  context.pointee.thread_count=1
  guard avcodec_open2(context,codec,nil)>=0 else { throw FilmAudioSampleError.decoder }
  streamIndex=chosen
  secondsPerTick=av_q2d(stream.pointee.time_base)
  guard secondsPerTick.isFinite,secondsPerTick>0 else { throw FilmAudioSampleError.decoder }
  packet=av_packet_alloc();frame=av_frame_alloc()
  guard packet != nil,frame != nil else { throw FilmAudioSampleError.decoder }
 }
 deinit {
  if resampler != nil { swr_free(&resampler) }
  if packet != nil { av_packet_free(&packet) }
  if frame != nil { av_frame_free(&frame) }
  if decoder != nil { avcodec_free_context(&decoder) }
  if format != nil { avformat_close_input(&format) }
 }

 func extract(at start:Double,length:Double=10) throws -> Clip {
  guard !Task.isCancelled else { throw FilmAudioSampleError.cancelled }
  guard let format,let decoder,let packet,let frame,
   start.isFinite,start>=0,length>=8,length<=12 else { throw FilmAudioSampleError.opening }
  let seekSeconds=max(0,start-1.0)
  let seekPTS=Int64((seekSeconds/secondsPerTick).rounded(.towardZero))
  var rc=av_seek_frame(format,streamIndex,seekPTS,AVSEEK_FLAG_BACKWARD)
  if rc<0 { rc=avformat_seek_file(format,streamIndex,Int64.min,seekPTS,Int64.max,AVSEEK_FLAG_BACKWARD) }
  guard rc>=0 else { throw FilmAudioSampleError.seek }
  avcodec_flush_buffers(decoder)
  if resampler != nil { swr_free(&resampler) }
  var pcm=Data()
  pcm.reserveCapacity(Int(length*16000*2))
  var firstTime:Double?
  var packetCount=0
  func consumeFrame() throws {
   defer { av_frame_unref(frame) }
   guard let rawPTS = frame.pointee.best_effort_timestamp == Int64.min ? nil : Optional(frame.pointee.best_effort_timestamp) else {return}
   let frameTime=Double(rawPTS)*secondsPerTick
   let rate=Int(frame.pointee.sample_rate)
   guard frameTime.isFinite,rate>0,frame.pointee.nb_samples>0 else{return}
   if frameTime>start+length+0.25 {return}
   if resampler == nil {
    var layout=AVChannelLayout()
    av_channel_layout_default(&layout,1)
    defer { av_channel_layout_uninit(&layout) }
    var inputLayout=frame.pointee.ch_layout
    guard swr_alloc_set_opts2(&resampler,&layout,AV_SAMPLE_FMT_S16,16000,
                             &inputLayout,AVSampleFormat(rawValue:frame.pointee.format),
                             Int32(rate),0,nil)>=0,
          let resampler,swr_init(resampler)>=0 else {throw FilmAudioSampleError.decoder}
   }
   guard let resampler else {throw FilmAudioSampleError.decoder}
   let capacity=Int((Double(frame.pointee.nb_samples)*16000/Double(rate)).rounded(.up))+64
   var converted=[UInt8](repeating:0,count:capacity*2)
   let count:Int32=converted.withUnsafeMutableBufferPointer { buffer in
    var out:UnsafeMutablePointer<UInt8>?=buffer.baseAddress
    let input=UnsafeRawPointer(frame.pointee.extended_data).assumingMemoryBound(to:UnsafePointer<UInt8>?.self)
    return withUnsafeMutablePointer(to:&out) {swr_convert(resampler,$0,Int32(capacity),input,frame.pointee.nb_samples)}
   }
   guard count>=0 else {throw FilmAudioSampleError.decoder}
   let valid=Int(count)
   let first=max(0,min(valid,Int(ceil((start-frameTime)*16000))))
   let last=max(first,min(valid,Int(ceil((start+length-frameTime)*16000))))
   guard last>first else{return}
   if firstTime == nil { firstTime=frameTime+Double(first)/16000 }
   let remaining=max(0,Int(length*16000*2)-pcm.count)
   let bytes=min((last-first)*2,remaining)
   if bytes>0 {pcm.append(contentsOf:converted[(first*2)..<(first*2+bytes)])}
  }
  while packetCount<12_000 && pcm.count<Int(length*16000*2) {
   if Task.isCancelled { throw FilmAudioSampleError.cancelled }
   guard av_read_frame(format,packet)>=0 else {break}
   packetCount+=1
   if packet.pointee.stream_index==streamIndex && avcodec_send_packet(decoder,packet)>=0 {
    while avcodec_receive_frame(decoder,frame)>=0 {try consumeFrame()}
   }
   av_packet_unref(packet)
  }
  // Missing audio must never be interpreted as a successful synchronisation.
  guard pcm.count>=Int(8*16000*2),let firstTime else { throw FilmAudioSampleError.insufficientAudio }
  return Clip(pcm16le:pcm,actualStartSeconds:firstTime)
 }
}
