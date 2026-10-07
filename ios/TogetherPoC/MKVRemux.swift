import Foundation
import AVFoundation
import PrismCore
import Libavutil
import Libavcodec

struct MKVAudioTrackPresentation: Equatable {
 let displayName: String
 let menuLabel: String
 let summary: String
}

// A preparation generation prevents a late playlist from replacing a new movie.
// The original account URL never becomes the room URL or a diagnostic string.
@MainActor final class MKVRemux {
 private var session: PrismCoreSession?
 private var generation=0
 private(set) var audioLabelsByDisplayName: [String:[String]] = [:]
 private(set) var audioTrackSummary: [String] = []
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
  audioLabelsByDisplayName=[:];audioTrackSummary=[]
  if let old=old {Task {await old.stop()}}
 }
 func prepare(_ url: URL,headers: [String:String]) async throws -> URL {
  stop();let g=generation
  // libav errors may otherwise contain the full authorized source URL.
  av_log_set_level(-8)
  let probed: ProbedSource
  do {
   probed=try await SourceProbe.openDetached(url:url,httpHeaders:headers)
  } catch {throw Self.safeFailure(error)}
  guard g==generation else {throw Failure.replaced}
  let sourceInfo=probed.info
  let current: PrismCoreSession
  do {
   current=try PrismCoreSession(
    url:url,httpHeaders:headers,display:.current(),segmentCacheBytes:256*1024*1024,
    probed:probed,reachability:.loopbackOnly
   )
  } catch {throw Self.safeFailure(error)}
  session=current
  do {
   let playlist=try await current.start(startupTimeout:.seconds(20))
   guard g==generation else {await current.stop();throw Failure.replaced}
   let objectFindings=await current.objectAudio
   let presentations=Self.audioPresentations(
    sourceInfo.audioTracks,deliveries:current.audioTrackDeliveries,objectFindings:objectFindings
   )
   audioLabelsByDisplayName=Dictionary(grouping:presentations,by:\.displayName).mapValues {$0.map(\.menuLabel)}
   audioTrackSummary=presentations.map(\.summary)
   return playlist
  } catch {
   await current.stop()
   if g==generation {session=nil;audioLabelsByDisplayName=[:];audioTrackSummary=[]}
   throw g==generation ? Self.safeFailure(error) : Failure.replaced
  }
 }
 static func audioPresentations(
  _ tracks: [AudioTrackInfo],deliveries: [AudioTrackDelivery],objectFindings: [ObjectAudioFinding] = []
 ) -> [MKVAudioTrackPresentation] {
  let deliveryByIndex=Dictionary(uniqueKeysWithValues:deliveries.map {($0.streamIndex,$0.delivery)})
  let objectByIndex=Dictionary(uniqueKeysWithValues:objectFindings.map {($0.streamIndex,$0.isObjectAudio)})
  return tracks.compactMap {track in
   guard let delivery=deliveryByIndex[track.streamIndex],
         delivery == .streamCopy || delivery == .bridged else {return nil}
   let displayName=sourceDisplayName(track)
   let confirmedObjectAudio=objectByIndex[track.streamIndex] ?? track.isObjectAudio
   let sourceCodec=humanCodec(track,objectAudio:confirmedObjectAudio)
   let channels=channelLabel(track.channelCount)
   let sampleRate=sampleRateLabel(track.sampleRate)
   var details=[sourceCodec]
   if !channels.isEmpty {details.append(channels)}
   if !sampleRate.isEmpty {details.append(sampleRate)}
   if delivery == .bridged {
    let target=bridgeTargetCodec()
    let objectNote=confirmedObjectAudio ? "，Atmos对象音频不保留" : ""
    var sourceParts=[sourceCodec]
    if !channels.isEmpty {sourceParts.append("源"+channels)}
    if !sampleRate.isEmpty {sourceParts.append(sampleRate)}
    let menu="\(displayName) · \(sourceParts.joined(separator:" · ")) → \(target)"
    let summary="\(displayName)：源 \(details.joined(separator:" · ")) → \(target)\(objectNote)"
    return MKVAudioTrackPresentation(displayName:displayName,menuLabel:menu,summary:summary)
   }
   return MKVAudioTrackPresentation(
    displayName:displayName,
    menuLabel:"\(displayName) · \(details.joined(separator:" · "))",
    summary:"\(displayName)：\(details.joined(separator:" · "))"
   )
  }
 }
 private static func sourceDisplayName(_ track: AudioTrackInfo) -> String {
  if let title=track.title?.trimmingCharacters(in:.whitespacesAndNewlines),!title.isEmpty {return title}
  if let language=track.language,language != "und",!language.isEmpty {
   return Locale.current.localizedString(forLanguageCode:language) ?? language
  }
  return "Audio \(track.streamIndex + 1)"
 }
 private static func humanCodec(_ track: AudioTrackInfo,objectAudio: Bool?=nil) -> String {
  let codec=track.codecName.lowercased()
  let profile=track.profileName?.trimmingCharacters(in:.whitespacesAndNewlines)
  let carriesObjects=objectAudio ?? track.isObjectAudio
  switch codec {
  case "aac": return "AAC"
  case "ac3": return "Dolby Digital (AC-3)"
  case "eac3": return carriesObjects ? "Dolby Digital Plus Atmos" : "Dolby Digital Plus (E-AC-3)"
  case "truehd","mlp": return carriesObjects ? "Dolby TrueHD Atmos" : "Dolby TrueHD"
  case "dts":
   if carriesObjects {
    if let profile=profile,!profile.isEmpty {return "DTS:X (\(profile))"}
    return "DTS:X"
   }
   if let profile=profile,!profile.isEmpty {return profile}
   return "DTS"
  case "flac": return "FLAC"
  case "alac": return "ALAC"
  case "opus": return "Opus"
  case "vorbis": return "Vorbis"
  case "mp3": return "MP3"
  case "mp2": return "MP2"
  default:
   if codec.hasPrefix("pcm_") {return "PCM"}
   if let profile=profile,!profile.isEmpty {return "\(codec.uppercased()) \(profile)"}
   return codec.isEmpty ? "音频编码未知" : codec.uppercased()
  }
 }
 private static func bridgeTargetCodec() -> String {
  avcodec_find_encoder(AV_CODEC_ID_EAC3) != nil ? "E-AC-3" : "AAC"
 }
 private static func channelLabel(_ count: Int) -> String {
  switch count {
  case 1:return "1.0"
  case 2:return "2.0"
  case 3:return "3.0"
  case 4:return "4.0"
  case 5:return "5.0"
  case 6:return "5.1"
  case 7:return "6.1"
  case 8:return "7.1"
  default:return count>0 ? "\(count)声道" : ""
  }
 }
 private static func sampleRateLabel(_ value: Int) -> String {
  guard value>0 else {return ""}
  if value%1000==0 {return "\(value/1000) kHz"}
  return String(format:"%.1f kHz",Double(value)/1000.0)
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
