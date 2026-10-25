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
  // The caller may have no subtitles yet. They are never needed for audio capture.
  _ = document
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
    let planned=SubtitleVerificationPlan.audioOnlySamples(duration:duration)
    guard planned.count==9 else {
     status="无法采集：请等待影片时长加载完成（至少 90 秒）";return
    }
    status="正在读取音轨"
    var clips:[(plan:SubtitleVerificationSample,pcm:Data,actualStart:Double)]=[]
    clips.reserveCapacity(9)
    for sample in planned {
     try Task.checkCancellation()
     let candidates=SubtitleVerificationPlan.audioOnlyCandidateStarts(
      for:sample,duration:duration)
     let clip=try await Task.detached(priority:.utility) {() throws -> FilmFFmpegAudioSampler.Clip in
      let sampler=try FilmFFmpegAudioSampler(url:movieURL)
      var best:FilmFFmpegAudioSampler.Clip?
      var highest=0.0
      var lastError:Error?
      for start in candidates {
       try Task.checkCancellation()
       do {
        let attempt=try sampler.extract(at:start,length:sample.durationSeconds)
        let estimate=FilmAudioSpeechActivity.score(pcm16le:attempt.pcm16le)
        if best == nil || estimate>highest {best=attempt;highest=estimate}
        if estimate>=0.16 {break}
       } catch {lastError=error}
      }
      guard let best else {throw lastError ?? FilmAudioSampleError.insufficientAudio}
      guard highest>=0.035 else {throw FilmAudioSampleError.insufficientAudio}
      return best
     }.value
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
                                subtitleSeconds:clip.actualStart,
                                audioStartSeconds:clip.actualStart)
     status="已上传 \(number+1)/9"
    }
    // The legacy X-Subtitle-Seconds header carries the AUDIO timestamp only.
    // No subtitle anchor exists here and the receiver must not treat it as one.
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
