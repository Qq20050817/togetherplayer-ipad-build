import Foundation
import Combine

/// Capture workflow is separate from playback and never changes subtitles.
/// Nine 16kHz mono PCM clips exist briefly in memory, then are uploaded by
/// HTTPS with a short-lived one-time grant. No file is stored on the iPad.
@MainActor final class SubtitleVerificationController:ObservableObject {
 @Published private(set) var status=""
 @Published private(set) var running=false
 private(set) var sampledCount=0

 func begin(movieURL:URL?,document:SubtitleDocument?,duration:Double,
            configuration:FilmAudioCaptureConfiguration) {
  guard !running else{return}
  guard let movieURL else {
   status="无法采集音轨：当前没有 iPad 能读取的电影片源";return
  }
  guard let document,!document.cues.isEmpty else {
   status="请先选择包含对白时间轴的字幕，以确定九个采样位置";return
  }
  running=true;sampledCount=0;status="正在检查影片"
  Task {
   defer {running=false}
   do {
    if !movieURL.isFileURL {
     guard ["http","https"].contains(movieURL.scheme?.lowercased() ?? "") else {
      status="无法采集音轨：当前片源不支持随机读取";return
     }
     var req=URLRequest(url:movieURL)
     req.setValue("bytes=0-0",forHTTPHeaderField:"Range")
     let result=try await FilmMaterialRangeRequest(limit:2048,expectedStatus:206)
      .fetchAsync(request:req,configuration:.ephemeral)
     guard let (data,response)=result,data.count==1,
      response.value(forHTTPHeaderField:"Content-Range")?.hasPrefix("bytes 0-0/")==true else {
      status="无法读取原片：源站不支持安全的 HTTP Range";return
     }
    }
    let planned=SubtitleVerificationPlan.samples(document:document,duration:duration)
    guard planned.count==9 else {
     status="无法采集：影片前、中、后没有足够的字幕对白供九段采样";return
    }
    status="正在读取音轨"
    var clips:[(plan:SubtitleVerificationSample,pcm:Data,actualStart:Double)]=[]
    clips.reserveCapacity(9)
    for sample in planned {
     try Task.checkCancellation()
     let clip=try await Task.detached(priority:.utility) {
      try FilmFFmpegAudioSampler(url:movieURL).extract(
       at:sample.startSeconds,length:sample.durationSeconds)
     }.value
     guard clip.pcm16le.count>=8*16000*2 else {
      throw FilmAudioSampleError.insufficientAudio
     }
     clips.append((sample,clip.pcm16le,clip.actualStartSeconds))
     sampledCount=sample.index
     status="已采样 \(sample.index)/9"
    }
    status="正在连接新加坡接收服务"
    let transport=FilmAudioCaptureTransport(configuration:configuration)
    let grant=try await transport.start()
    status="正在安全上传音轨"
    for (number,clip) in clips.enumerated() {
     try Task.checkCancellation()
     try await transport.upload(grant:grant,index:clip.plan.index,pcm:clip.pcm,
                                subtitleSeconds:clip.plan.subtitleStartSeconds,
                                audioStartSeconds:clip.actualStart)
     status="已上传 \(number+1)/9"
    }
    // The receiver may not have ASR configured. Audio upload is the only
    // promised success; never claim a subtitle sync check took place.
    _ = try await transport.finish(grant:grant)
    clips.removeAll(keepingCapacity:false)
    status="九段音轨已上传新加坡服务器；原字幕未修改"
   } catch {
    status="音轨采集或上传未完成：\(error.localizedDescription)。原字幕保持不变"
   }
  }
 }
}
