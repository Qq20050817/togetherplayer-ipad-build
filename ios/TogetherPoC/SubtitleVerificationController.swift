import Foundation
import Combine

/// Isolated from playback/sync. A failure cannot alter the selected subtitle.
@MainActor final class SubtitleVerificationController:ObservableObject {
 @Published private(set) var status=""
 @Published private(set) var running=false
 private(set) var sampledCount=0

 func begin(movieURL:URL?,document:SubtitleDocument?,duration:Double) {
  guard !running else{return}
  guard let movieURL else {status="无法读取原片：当前房间没有可访问的影片地址";return}
  guard let document,!document.cues.isEmpty else {
   status="无法验证：所选字幕没有完整可用的时间轴，原字幕保持不变";return
  }
  running=true;sampledCount=0;status="正在检查影片"
  Task {
   defer {running=false}
   do {
    if !movieURL.isFileURL {
     guard ["http","https"].contains(movieURL.scheme?.lowercased() ?? "") else {
      status="无法读取原片：当前来源不支持随机读取";return
     }
     var req=URLRequest(url:movieURL)
     req.setValue("bytes=0-0",forHTTPHeaderField:"Range")
     let result=try await FilmMaterialRangeRequest(limit:2048,expectedStatus:206)
      .fetchAsync(request:req,configuration:.ephemeral)
     guard let (data,response)=result,data.count==1,
       response.value(forHTTPHeaderField:"Content-Range")?.hasPrefix("bytes 0-0/")==true else {
      status="无法读取原片：HTTP 服务不支持可靠的 Range，已阻止全片下载";return
     }
    }
    let planned=SubtitleVerificationPlan.samples(document:document,duration:duration)
    guard planned.count==9 else {
     status="无法验证：影片前、中、后没有足够的字幕对白用于九段采样";return
    }
    status="正在读取音轨"
    for sample in planned {
     try Task.checkCancellation()
     // One clip at a time, retained in RAM only. The temporary PCM is dropped
     // after this step; no audio, media URL or credentials are persisted.
     let clip=try await Task.detached(priority:.utility) {
      try FilmFFmpegAudioSampler(url:movieURL).extract(at:sample.startSeconds,length:sample.durationSeconds)
     }.value
     guard clip.pcm16le.count>=8*16000*2 else {throw FilmAudioSampleError.insufficientAudio}
     sampledCount=sample.index
     status="已采样 \(sample.index)/9"
    }
    // A real server verifier must return a signed, evidence-backed result.
    // Until paired HTTPS one-time authorization is available, do not claim
    // that speech and captions were compared or emit a corrected SRT.
    status="音轨九段采样完成；新加坡校验服务尚未配对，原字幕保持不变"
   } catch {
    status="无法读取原片：\(error.localizedDescription)，原字幕保持不变"
   }
  }
 }
}
