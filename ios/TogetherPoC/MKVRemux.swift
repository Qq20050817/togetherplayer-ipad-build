import Foundation
import AVFoundation
import PrismCore
import Libavutil

// A preparation generation prevents a late playlist from replacing a new movie.
// The original account URL never becomes the room URL or a diagnostic string.
@MainActor final class MKVRemux {
 private var session: PrismCoreSession?
 private var generation=0
 enum Failure: LocalizedError {
  case replaced, preparation
  case diagnostic(String)
  var errorDescription: String? {
   if case .diagnostic(let message)=self {return message}
   return "本机片源准备失败（原因未分类）；可在房间设置中重试。"
  }
 }
 func stop() {
  generation += 1
  let old=session;session=nil
  if let old=old {Task {await old.stop()}}
 }
 func prepare(_ url: URL,headers: [String:String]) async throws -> URL {
  stop();let g=generation
  // libav errors may otherwise contain the full authorized source URL.
  av_log_set_level(-8)
  let current: PrismCoreSession
  do {
   current=try PrismCoreSession(url:url,httpHeaders:headers,display:.current(),segmentCacheBytes:256*1024*1024,reachability:.loopbackOnly)
  } catch {throw Self.safeFailure(error)}
  session=current
  do {
   let playlist=try await current.start(startupTimeout:.seconds(20))
   guard g==generation else {await current.stop();throw Failure.replaced}
   return playlist
  } catch {
   await current.stop()
   if g==generation {session=nil}
   throw g==generation ? Self.safeFailure(error) : Failure.replaced
  }
 }
 // Never expose underlying descriptions: they can contain signed account URLs.
 static func safeFailure(_ error: Error) -> Failure {
  let reason: String
  switch PrismCoreError.classify(error) {
  case .originRefused(let status,_):
   reason="片源拒绝访问"+(status.map {"（HTTP \($0)）"} ?? "")+"；请重新授权并选片。"
  case .originRateLimited(let status,_,_):
   reason="片源限流（HTTP \(status)）；请稍后手动重试。"
  case .originUnreachable(let status,_,_):
   reason="片源读取失败"+(status.map {"（HTTP \($0)）"} ?? "")+"；请检查网络并重新选片。"
  case .startupBudgetExpired:
   reason="兼容准备超时；20秒内未生成播放清单，可手动重试。"
  case .noVideoStream: reason="未检测到视频轨道。"
  case .videoCodecNotRemuxable, .videoCodecUnplayable:
   reason="当前兼容播放路径不支持此视频编码。"
  case .workDirectoryOutOfSpace: reason="本机可用空间不足，请清理空间。"
  case .masterRejectedByPlayer: reason="系统播放器拒绝本机播放清单。"
  case .ffmpeg(let code,_,_): reason="封装处理失败（FFmpeg \(code)）；请保留此错误码。"
  case .unknown: reason="原因未分类；可在房间设置中手动重试。"
  }
  return .diagnostic("本机片源准备失败："+reason)
 }
 static func needed(url: URL,fileName: String?=nil) -> Bool {
  if let fileName=fileName {return (fileName as NSString).pathExtension.lowercased()=="mkv"}
  return url.pathExtension.lowercased()=="mkv"
 }
}
