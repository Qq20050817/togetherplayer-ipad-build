import Foundation
import AVFoundation

protocol PlayerAdapter: AnyObject {
 func play(); func pause(); func seekTo(_ milliseconds: Double)
 var position: Double { get }; var duration: Double { get }
 var buffering: Bool { get }; var ready: Bool { get }
 func setPlaybackSpeed(_ speed: Float)
}
protocol MediaSourceAdapter { func resolve(_ url: String) -> URL? }
struct HTTPSource: MediaSourceAdapter {
 func resolve(_ url: String) -> URL? {
  guard let value = URL(string: url), ["http", "https"].contains(value.scheme ?? ""),value.host?.isEmpty == false else { return nil }
  return value
 }
}
final class AVPlayerAdapter: PlayerAdapter {
 let player: AVPlayer
 init(player: AVPlayer = AVPlayer()) {self.player=player}
 private var seeking = false
 private var speed: Float = 1
 private var playRequested=false
 var position: Double { let n = player.currentTime().seconds*1000; return n.isFinite ? n : 0 }
 var duration: Double { let n=(player.currentItem?.duration.seconds ?? 0)*1000;return n.isFinite && n>0 ? n : 0 }
 // Only contiguous data at the playhead can cover playback; later disjoint ranges cannot.
 var bufferedAheadMs: Double {
  let position=player.currentTime().seconds
  guard position.isFinite else {return 0}
  let ranges=(player.currentItem?.loadedTimeRanges ?? []).map { $0.timeRangeValue }.sorted {$0.start.seconds < $1.start.seconds}
  var end=position
  for range in ranges {
   let start=range.start.seconds, stop=CMTimeRangeGetEnd(range).seconds
   guard start.isFinite,stop.isFinite else {continue}
   if start <= end+0.05 && stop > end {end=stop}
  }
  return max(0,(end-position)*1000)
 }
 var buffering: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
 var ready: Bool { player.currentItem?.status == .readyToPlay && !seeking }
 func play() { if !playRequested || player.timeControlStatus == .paused { player.defaultRate=speed;player.play() };playRequested=true }
 func pause() { if playRequested || player.rate != 0 {player.pause()};playRequested=false }
 func setPlaybackSpeed(_ value: Float) {
  speed = value
  if player.timeControlStatus == .playing && player.rate != value { player.rate = value }
 }
 func seekTo(_ milliseconds: Double) {
  guard !seeking else { return }; seeking = true
  player.seek(to: CMTime(seconds: milliseconds/1000, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
   DispatchQueue.main.async { self?.seeking = false }
  }
 }
}
struct Timeline: Codable {
 let state: String; let position: Double; let updatedAt: Double; let playbackRate: Double
 func at(_ now: Double) -> Double { max(0, position + (state == "playing" ? max(0, now-updatedAt)*playbackRate : 0)) }
}
struct Room: Codable {
 let roomId: String; let hostId: String; let mediaUrl: String; let version: Int64; let executeAt: Double
 let state: String; let position: Double; let updatedAt: Double; let playbackRate: Double; let before: Timeline
 var title: String?=nil;var duration: Double?=nil;var waitForPeer: Bool?=nil;var pauseReason: String?=nil;var autoResume: Bool?=nil
 func target(_ now: Double) -> (Double,String) {
  if now < executeAt { return (before.at(now),before.state) }
  return (Timeline(state: state, position: position, updatedAt: updatedAt, playbackRate: playbackRate).at(now), state)
 }
}
final class ClockSync {
 private let monotonicNow: () -> Double
 private var samples: [(Double,Double)] = []
 private(set) var offset = 0.0
 private(set) var rtt = 0.0
 var ready: Bool { !samples.isEmpty }
 init(_ monotonicNow: @escaping () -> Double = {ProcessInfo.processInfo.systemUptime*1000}) {self.monotonicNow=monotonicNow}
 func localNow() -> Double { monotonicNow() }
 func serverNow() -> Double { localNow()+offset }
 func reset() { samples.removeAll() }
 func add(_ t1: Double,_ t2: Double,_ t3: Double,_ t4: Double) {
  let latency=(t4-t1)-(t3-t2)
  guard latency >= 0 && latency <= 5000 else { return }
  samples.append((((t2-t1)+(t3-t4))/2,latency));if samples.count > 8 { samples.removeFirst() }
  offset=samples.min(by: {$0.1 < $1.1})!.0; rtt=latency
 }
}
final class SyncEngine {
 private(set) var room: Room?
 var timelineOffset=0.0 {didSet {if oldValue != timelineOffset {resetCorrection();lastAutoSeekAt=nil}}}
 private var correctionSpeed: Float = 1
 private var excessiveDriftSince: Double?
 private var driftAtWindowStart=0.0
 private var lastAutoSeekAt: Double?
 private var wasUnready=false
 private var settleUntil=0.0
 private(set) var resyncCount = 0
 let clock: ClockSync; let player: PlayerAdapter
 init(_ player: PlayerAdapter,_ clock: ClockSync) { self.player=player;self.clock=clock }
 func resetSession() {
  player.pause();player.setPlaybackSpeed(1);clock.reset();room=nil;lastAutoSeekAt=nil;wasUnready=false;settleUntil=0;resetCorrection()
 }
 func receive(_ next: Room) {
  if next.roomId != room?.roomId || next.version >= (room?.version ?? 0) {
   if next.roomId != room?.roomId || next.version != room?.version {lastAutoSeekAt=nil;resetCorrection()}
   room=next
  }
 }
 private func resetCorrection() { correctionSpeed=1;excessiveDriftSince=nil }
 // Keep a correction speed until the error is well inside the lower band.
 // AVPlayer rate changes can stall briefly; switching at a single threshold
 // can undo the progress of the preceding speed correction.
 private func speed(for error: Double) -> Float {
  let magnitude=abs(error)
  let sameDirection=(error>0 && correctionSpeed>1) || (error<0 && correctionSpeed<1)
  let wasFast=abs(correctionSpeed-1)>0.03
  let correcting=abs(correctionSpeed-1)>0.001
  let fast=magnitude>=500 || (sameDirection && wasFast && magnitude>250)
  let gentle=magnitude>=200 || (sameDirection && correcting && magnitude>100)
  correctionSpeed=fast ? (error>0 ? 1.05 : 0.95) : gentle ? (error>0 ? 1.02 : 0.98) : 1
  return correctionSpeed
 }
 func target() -> (Double,String)? {
  guard clock.ready,let result=room?.target(clock.serverNow()) else {return nil}
  let localPosition=max(0,result.0+timelineOffset)
  let duration=player.duration
  if duration.isFinite && duration>0 && localPosition>=duration {return (duration,"paused")}
  return (localPosition,result.1)
 }
 @discardableResult func tick() -> Double? {
  guard let (position,state)=target() else {excessiveDriftSince=nil;return nil}
  let error=position-player.position
  let now=clock.localNow()
  if !player.ready || player.buffering {wasUnready=true}
  else if wasUnready {wasUnready=false;settleUntil=now+2000}
  if state == "paused" { resetCorrection();player.pause();player.setPlaybackSpeed(1);guard player.ready else {return nil};if abs(error)>200 {player.seekTo(position)};return error }
  guard player.ready && !player.buffering else {excessiveDriftSince=nil;return nil}
  if now<settleUntil {resetCorrection();player.setPlaybackSpeed(1);player.play();return error}
  if abs(error)>=500 {if excessiveDriftSince == nil {excessiveDriftSince=now;driftAtWindowStart=abs(error)}} else {excessiveDriftSince=nil}
  var overdue=excessiveDriftSince.map {now-$0>=10_000} ?? false
  if overdue && driftAtWindowStart-abs(error)>=100 {
   excessiveDriftSince=now;driftAtWindowStart=abs(error);overdue=false
  }
  let canSeek=lastAutoSeekAt.map {now-$0>=3000} ?? true
  if (abs(error)>1500 || overdue) && canSeek {
   player.seekTo(position);player.setPlaybackSpeed(1);resetCorrection();lastAutoSeekAt=now;resyncCount += 1
  } else {player.setPlaybackSpeed(speed(for:error))}
  player.play();return error
 }
}

// A non-empty buffer alone must not trigger a room-wide automatic resume.
enum RecoveryBufferPolicy {
 static func ready(prepared: Bool,bufferedMs: Double,positionMs: Double,durationMs: Double,recovering: Bool,preparedFallback: Bool=false) -> Bool {
  guard prepared else {return false}
  guard recovering else {return true}
  guard bufferedMs.isFinite,positionMs.isFinite else {return false}
  let remaining=durationMs.isFinite && durationMs>0 ? max(0,durationMs-positionMs) : 12000
  let required=min(12000,remaining)
  return max(0,bufferedMs)+50 >= required || (preparedFallback && max(0,bufferedMs)+50 >= min(3000,required))
 }
}

// A stale AVPlayerItem buffer-empty hint must not outweigh observed playback
// or contiguous data. Actual waiting remains authoritative during playback.
struct PlaybackReadiness {
 let ready: Bool
 let buffering: Bool
}
enum PlaybackReadinessPolicy {
 static func evaluate(prepared: Bool,waiting: Bool,playing: Bool,bufferEmpty: Bool,bufferedMs: Double,positionMs: Double,durationMs: Double,recovering: Bool,preparedFallback: Bool=false) -> PlaybackReadiness {
  if recovering {
   let ready=RecoveryBufferPolicy.ready(prepared:prepared,bufferedMs:bufferedMs,positionMs:positionMs,durationMs:durationMs,recovering:true,preparedFallback:preparedFallback)
   return PlaybackReadiness(ready:ready,buffering:!ready)
  }
  let remaining=durationMs.isFinite && durationMs>0 && positionMs.isFinite ? max(0,durationMs-positionMs) : 1000
  let finished=durationMs.isFinite && durationMs>0 && positionMs.isFinite && positionMs+50>=durationMs
  let hasData=finished || (bufferedMs.isFinite && bufferedMs>0 && bufferedMs+50 >= min(1000,remaining))
  let depleted=bufferEmpty && !playing && !hasData
  return PlaybackReadiness(ready:prepared && !waiting && !depleted,buffering:waiting || (prepared && depleted))
 }
}
