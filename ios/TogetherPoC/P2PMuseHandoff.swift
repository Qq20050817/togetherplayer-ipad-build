import Foundation

/// Bounds the temporary handoff after an authenticated P2P control hint.
/// The Muse timeline remains authoritative once the command takes effect,
/// the room changes, a safety pause arrives, or the short timeout expires.
struct P2PMuseHandoff {
 static let maximumHoldMs: Double = 3_500
 private var pendingAction: P2PPlaybackAction?
 private var roomID = ""
 private var baseVersion: Int64 = 0
 private var desiredPositionMs: Double = 0
 private var expiresAtMs: Double = 0

 mutating func begin(_ hint: P2PControlHint, timelineOffset: Double, now: Double) {
  guard now.isFinite, timelineOffset.isFinite else {reset();return}
  pendingAction=hint.action
  roomID=hint.roomID
  baseVersion=hint.roomVersion
  desiredPositionMs=hint.positionMs+timelineOffset
  expiresAtMs=now+Self.maximumHoldMs
 }

 mutating func reset() {
  pendingAction=nil;roomID="";baseVersion=0
  desiredPositionMs=0;expiresAtMs=0
 }

 mutating func shouldDeferMuse(now: Double, roomID: String, roomVersion: Int64,
                              targetState: String?, targetPositionMs: Double?,
                              blockingPoll: Bool, authoritativePause: Bool) -> Bool {
  guard let action=pendingAction else{return false}
  // A room change, plot question, or explicit server safety pause wins now.
  guard now.isFinite,roomID==self.roomID,!blockingPoll,!authoritativePause else {reset();return false}
  guard now<expiresAtMs else {reset();return false}
  if roomVersion>baseVersion {
   // If more than one server transition happened, newer commands win.
   guard roomVersion==baseVersion+1 else {reset();return false}
   let acknowledged:Bool
   switch action {
   case .play: acknowledged=targetState=="playing"
   case .pause: acknowledged=targetState=="paused"
   case .seek:
    acknowledged=targetPositionMs.map {$0.isFinite && abs($0-desiredPositionMs)<=1_000} ?? false
   }
   if acknowledged {reset();return false}
  }
  // Old Muse snapshots must not undo a just-rendered P2P action.
  // The hold is bounded even if a Muse ACK is lost.
  return true
 }
}
