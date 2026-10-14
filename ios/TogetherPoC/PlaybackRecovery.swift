import Foundation

// Observes actual progress independently of the room's nominal playing state.
// Pauses and answer locks disarm recovery. Each stuck episode gets a cheap
// player wake-up first, then one last-resort item rebuild without reimporting.
struct PlaybackRecovery {
 enum Action: Equatable {case none, wake, rebuild}
 private(set) var stalledSince: Double?
 private var lastPosition: Double?
 private var recoveryStage = 0
 mutating func reset() {stalledSince=nil;lastPosition=nil;recoveryStage=0}
 mutating func observe(now: Double,position: Double,shouldPlay: Bool) -> Action {
  guard shouldPlay,now.isFinite,position.isFinite else {reset();return .none}
  if let last=lastPosition,abs(position-last)>=150 {
   stalledSince=now;lastPosition=position;recoveryStage=0;return .none
  }
  if lastPosition==nil {lastPosition=position;stalledSince=now;return .none}
  let elapsed=now-(stalledSince ?? now)
  if elapsed>=14_000 && recoveryStage==1 {recoveryStage=2;return .rebuild}
  if elapsed>=5_000 && recoveryStage==0 {recoveryStage=1;return .wake}
  return .none
 }
}
