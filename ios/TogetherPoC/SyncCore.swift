import Foundation
import AVFoundation

// Timer callbacks may queue while decoding or a UI transition holds the main
// actor. Keep one pending refresh, rather than replaying stale refreshes later.
final class MainActorPulse: @unchecked Sendable {
 private let lock=NSLock()
 private var pending=false
 func request(_ action:@escaping @MainActor @Sendable ()->Void) {
  lock.lock()
  if pending {lock.unlock();return}
  pending=true;lock.unlock()
  Task {@MainActor [self] in
   defer {finish()}
   action()
  }
 }
 private func finish() {lock.lock();pending=false;lock.unlock()}
}

protocol PlayerAdapter: AnyObject {
 func play(); func pause(); func seekTo(_ milliseconds: Double)
 var position: Double { get }; var duration: Double { get }
 var buffering: Bool { get }; var ready: Bool { get }
 // Only the native transport knows whether the decoder has actually started.
 var nativePlaybackRunning: Bool { get }
 func setPlaybackSpeed(_ speed: Float)
}
extension PlayerAdapter {
 // Preserve legacy mocked adapters used by the independent sync tests.
 var nativePlaybackRunning: Bool { true }
}
protocol MediaSourceAdapter { func resolve(_ url: String) -> URL? }
struct HTTPSource: MediaSourceAdapter {
 func resolve(_ url: String) -> URL? {
  guard let value = URL(string: url), ["http", "https"].contains(value.scheme ?? ""),value.host?.isEmpty == false else { return nil }
  return value
 }
}
// Coalesce slider bursts so only the newest seek survives while decoding.
struct SeekRequestBuffer {
 private(set) var pending: Double?
 @discardableResult mutating func replace(_ milliseconds: Double,duration: Double) -> Bool {
  guard milliseconds.isFinite else {return false}
  // A duration may be unknown while an asset is loading. Keep CMTime bounded.
  let upper=duration.isFinite && duration>0 ? duration : 86_400_000
  pending=min(upper,max(0,milliseconds))
  return true
 }
 mutating func takeLatest() -> Double? {
  let latest=pending;pending=nil;return latest
 }
 mutating func clear() {pending=nil}
}
// AVPlayer may report .paused for several ticks while transitioning to a new
// decoder item. A room tick every 100 ms must never issue a play storm.
struct PlaybackStartGate {
 private(set) var requested=false
 private var lastStartAt = -Double.infinity
 mutating func shouldStart(now:Double,prepared:Bool,paused:Bool)->Bool {
  guard prepared,now.isFinite else {return false}
  if requested && (!paused || now-lastStartAt<750) {return false}
  requested=true;lastStartAt=now;return true
 }
 mutating func reset() {requested=false;lastStartAt = -.infinity}
}
final class AVPlayerAdapter: PlayerAdapter {
 let player: AVPlayer
 init(player: AVPlayer = AVPlayer()) {self.player=player}
 var seekObserved:(()->Void)?
 var seekResult:((Bool,String)->Void)?
 private var seekDeadline:DispatchWorkItem?
 private var seekSerial=0
 private var seekRetry=0
 private var seeking = false
 private var seekEpoch = 0
 private var seekBuffer = SeekRequestBuffer()
 private var speed: Float = 1
 private var startGate=PlaybackStartGate()
 private var resumeAfterSeek=false
 var isSeeking:Bool {seeking || seekBuffer.pending != nil}
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
 var ready: Bool { player.currentItem?.status == .readyToPlay && !isSeeking }
 var nativePlaybackRunning: Bool { player.timeControlStatus == .playing }
 // All mutations use one queue. An off-main request belongs to the item it
 // saw, and must never execute against a replacement film.
 private func deferToMain(_ action:@escaping(AVPlayerAdapter)->Void)->Bool {
  guard !Thread.isMainThread else {return false}
  let item=player.currentItem
  DispatchQueue.main.async { [weak self] in
   guard let self,self.player.currentItem === item else {return}
   action(self)
  }
  return true
 }
 func play() {
  if deferToMain({$0.play()}) {return}
  guard let item=player.currentItem,item.status == .readyToPlay,
        item.error == nil,player.error == nil else {return}
  if isSeeking {
   resumeAfterSeek=true
   if !seeking {performNextSeek()}
   return
  }
  guard startGate.shouldStart(now:ProcessInfo.processInfo.systemUptime*1000,
        prepared:true,paused:player.timeControlStatus == .paused) else {return}
  if abs(player.defaultRate-speed)>0.001 {player.defaultRate=speed}
  player.play()
 }
 func pause() {
  if deferToMain({$0.pause()}) {return}
  resumeAfterSeek=false
  if startGate.requested || player.rate != 0 {player.pause()}
  startGate.reset()
 }
 func setPlaybackSpeed(_ value: Float) {
  guard value.isFinite,value>0,value<=2.5 else {return}
  if deferToMain({$0.setPlaybackSpeed(value)}) {return}
  speed=value
  // Keep the requested rate, but do not reconfigure the decoder during seek
  // or item preparation. play()/itemBecameReady applies it at a safe boundary.
  guard !isSeeking,player.error == nil,
        player.currentItem == nil || (player.currentItem?.status == .readyToPlay && player.currentItem?.error == nil) else {return}
  // Avoid rewriting defaultRate/rate on every 100 ms sync tick: AVFoundation
  // can briefly reconfigure audio/video decoding on repeated rate writes.
  if abs(player.defaultRate-value)>0.001 {player.defaultRate=value}
  if player.timeControlStatus == .playing && abs(player.rate-value)>0.001 {player.rate=value}
 }
 // Called before replacing a movie. A delayed completion must not seek its replacement.
 func resetPendingSeeks() {
  if deferToMain({$0.resetPendingSeeks()}) {return}
  seekDeadline?.cancel();seekDeadline=nil;seekSerial &+= 1;seekRetry=0
  seekEpoch &+= 1
  seekBuffer.clear()
  seeking=false
  resumeAfterSeek=false
  player.currentItem?.cancelPendingSeeks()
  startGate.reset()
 }
 func seekTo(_ milliseconds: Double) {
  guard milliseconds.isFinite else {return}
  if deferToMain({$0.seekTo(milliseconds)}) {return}
  guard let item=player.currentItem,item.status != .failed,
        item.error == nil,player.error == nil else {seekResult?(false,"片源尚未就绪或读取失败");return}
  seekObserved?()
  seekRetry=0
  let firstRequest = !isSeeking
  guard seekBuffer.replace(milliseconds,duration:duration) else {return}
  if firstRequest {
   resumeAfterSeek=startGate.requested || player.rate>0 || player.timeControlStatus != .paused
  }
  if !seeking {performNextSeek()}
  if seekBuffer.pending != nil && !seeking {armSeekDeadline()}
 }
 private func armSeekDeadline() {
  seekDeadline?.cancel();seekSerial &+= 1
  let serial=seekSerial,epoch=seekEpoch
  let deadline=DispatchWorkItem { [weak self] in
   guard let self,self.seekSerial==serial,self.seekEpoch==epoch,self.isSeeking else{return}
   self.resetPendingSeeks();self.seekResult?(false,"跳转超时，请检查片源读取和网络后重试")
  }
  seekDeadline=deadline;DispatchQueue.main.asyncAfter(deadline:.now()+15,execute:deadline)
 }
 func itemBecameReady(_ item:AVPlayerItem) {
  if deferToMain({$0.itemBecameReady(item)}) {return}
  guard player.currentItem === item,item.status == .readyToPlay,
        item.error == nil,player.error == nil else {return}
  if !seeking,seekBuffer.pending != nil {performNextSeek()}
  else if !isSeeking {setPlaybackSpeed(speed)}
 }
 private func performNextSeek() {
  guard let item=player.currentItem,item.status == .readyToPlay,
        item.error == nil,player.error == nil else {seeking=false;return}
  guard let target=seekBuffer.takeLatest() else {seeking=false;return}
  seeking=true;armSeekDeadline()
  // Pause once for the whole burst. No PLAY/rate write runs between its
  // intermediate completions; an explicit PAUSE can cancel resume intent.
  if startGate.requested || player.rate != 0 {player.pause()}
  startGate.reset()
  let epoch=seekEpoch
  // Exact-frame decoding on each rapid jump is expensive for 4K/HDR video.
  let tolerance=CMTime(value:1,timescale:10)
  player.seek(to:CMTime(seconds:target/1000,preferredTimescale:600),toleranceBefore:tolerance,toleranceAfter:tolerance) { [weak self,weak item] finished in
   DispatchQueue.main.async {
    guard let self=self,epoch==self.seekEpoch else {return}
    guard self.player.currentItem === item else {
     self.seekBuffer.clear();self.seeking=false;return
    }
    self.seekDeadline?.cancel();self.seekDeadline=nil
    self.seeking=false
    if self.seekBuffer.pending != nil {self.seekRetry=0;self.performNextSeek();return}
    let confirmed=finished && abs(self.position-target)<=250
    if !confirmed {
     if self.seekRetry<1 {
      self.seekRetry+=1;self.seekBuffer.replace(target,duration:self.duration);self.performNextSeek()
     } else {
      self.resumeAfterSeek=false;self.seekResult?(false,"播放器未确认跳转，可能存在片源或 HTTP Range 读取异常")
     }
     return
    }
    self.seekRetry=0;self.seekResult?(true,"")
    if self.resumeAfterSeek {
     self.resumeAfterSeek=false;self.play()
    } else {self.setPlaybackSpeed(self.speed)}
   }
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
// A sampled five-second gap must persist for ten seconds before catch-up.
// User SEEK bypasses this policy; only the lagging device changes speed.
struct SustainedCatchupPolicy {
 private var since:Double?;private var last:Double?;private var rate:Float=1
 mutating func reset(){since=nil;last=nil;rate=1}
 mutating func speed(error:Double,now:Double)->Float {
  guard error.isFinite,now.isFinite else {reset();return 1}
  if let last,now<last || now-last>1000 {since=nil;rate=1}
  last=now
  if error<=3000 {since=nil;rate=1;return 1}
  if rate>1 {return rate}
  if error<=5000 {since=nil;return 1}
  if since==nil {since=now}
  if now-(since ?? now)>=10000 {rate=error>15000 ? 1.25 : 1.10}
  return rate
 }
}
final class SyncEngine {
 private(set) var room: Room?
 var timelineOffset=0.0 {didSet {if oldValue != timelineOffset {resetCorrection();lastAutoSeekAt=nil}}}
 private var explicitSeekVersion: Int64?
 private var catchup=SustainedCatchupPolicy()
 private var excessiveDriftSince: Double?
 private var driftAtWindowStart=0.0
 private var lastAutoSeekAt: Double?
 private var wasUnready=false
 private var settleUntil=0.0
 private(set) var resyncCount = 0
 let clock: ClockSync; let player: PlayerAdapter
 init(_ player: PlayerAdapter,_ clock: ClockSync) { self.player=player;self.clock=clock }
 func resetSession() {
  player.pause();player.setPlaybackSpeed(1);clock.reset();room=nil;explicitSeekVersion=nil;lastAutoSeekAt=nil;wasUnready=false;settleUntil=0;resetCorrection()
 }
 func receive(_ next: Room) {
  if next.roomId != room?.roomId || next.version >= (room?.version ?? 0) {
   let previous=room
   if next.roomId != previous?.roomId || next.version != previous?.version {lastAutoSeekAt=nil;resetCorrection()}
   // Give a newly scheduled PLAY time to render its first frames before
   // making any speed change / hard seek. Normal seek commands while already
   // playing remain immediate and are not given this startup grace period.
   if next.state == "playing" && previous?.roomId == next.roomId {
    if previous?.state == "paused" {settleUntil=clock.localNow()+2000}
    // Rate changes can stall AVPlayer's decoder, particularly at 2x on 4K.
    // Give a new shared speed time to settle before drift correction seeks.
    else if next.playbackRate != previous?.playbackRate {settleUntil=clock.localNow()+2500}
   }
   if next.roomId != previous?.roomId || next.mediaUrl != previous?.mediaUrl {
    explicitSeekVersion=next.version
   } else if next.version > (previous?.version ?? 0) {
    // Timeline discontinuity identifies an explicit room jump, including
    // jumps smaller than the automatic three-second tolerance.
    let previousPosition=next.before.at(next.updatedAt)
    explicitSeekVersion=abs(next.position-previousPosition)>150 ? next.version : nil
   }
   room=next
  }
 }
 private func resetCorrection() { catchup.reset();excessiveDriftSince=nil }
 // Keep a correction speed until the error is well inside the lower band.
 // AVPlayer rate changes can stall briefly; switching at a single threshold
 // can undo the progress of the preceding speed correction.
 private func speed(for error: Double) -> Float {catchup.speed(error:error,now:clock.localNow())}

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
  let timeline=clock.serverNow() < (room?.executeAt ?? 0) ? room?.before.playbackRate : room?.playbackRate
  let baseRate:Float=timeline == 2 ? 2 : 1
  if explicitSeekVersion != nil {
   // Suppress old before-timeline correction after a local optimistic seek.
   guard clock.serverNow() >= (room?.executeAt ?? 0) else {if state == "playing" {player.play()} else {player.pause()};return error}
   if state == "paused" {player.pause();player.setPlaybackSpeed(1)}
   guard player.ready || player.buffering else {return nil}
   explicitSeekVersion=nil;resetCorrection();lastAutoSeekAt=now
   if abs(error)>150 {player.seekTo(position)}
   player.setPlaybackSpeed(baseRate)
   if state == "paused" {player.pause()} else {player.play()}
   return error
  }
  if !player.ready || player.buffering {wasUnready=true;catchup.reset()}
  else if wasUnready {wasUnready=false;settleUntil=now+2000}
  if state == "paused" { resetCorrection();player.pause();player.setPlaybackSpeed(1);guard player.ready else {return nil};if abs(error)>3000 && lastAutoSeekAt == nil {lastAutoSeekAt=now;player.seekTo(position)};return error }
  guard player.ready else {excessiveDriftSince=nil;return nil}
  if player.buffering {
   // Preserve play intent while AVPlayer waits for data. The player can
   // otherwise remain stuck in waiting with no subsequent play attempt.
   player.play();excessiveDriftSince=nil;return nil
  }
  // A ready HLS item can hold dozens of seconds of buffered media yet still
  // have rendered no first frame. Hard-seeking every three seconds in that
  // state cancels decoder startup indefinitely. Let the native player advance
  // off zero before applying large room-clock corrections.
  if !player.nativePlaybackRunning || (player.position < 100 && abs(error)>1500) {
   resetCorrection()
   player.setPlaybackSpeed(baseRate)
   player.play()
   return error
  }
  if now<settleUntil {resetCorrection();player.setPlaybackSpeed(baseRate);player.play();return error}
  // Automatic drift correction uses speed only; explicit jumps were handled
  // above. Never issue a repeated hard-seek loop while a decoder catches up.
  player.setPlaybackSpeed(min(2.5,baseRate*speed(for:error)))
  player.play();return error
 }
}

// A non-empty buffer alone must not trigger a room-wide automatic resume.
enum RecoveryBufferPolicy {
 // AVPlayer preroll requires a paused player. A transient rate of zero while
 // waiting/seeking is not a safe paused state, nor is a scheduled PLAY.
 static func canPreroll(prepared:Bool,pausedIntent:Bool,nativePaused:Bool,controlPending:Bool)->Bool {
  prepared && pausedIntent && nativePaused && !controlPending
 }
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
