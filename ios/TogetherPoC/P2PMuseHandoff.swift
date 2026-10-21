import Foundation

// A P2P hint is only a short-lived speculative preview. The Muse room is
// authoritative. Do not replay its *old* timeline while the server is
// scheduling the matching command, or AVPlayer may pause/seek twice.
struct P2PMuseHandoff {
 private struct Pending {
  let roomID: String
  let mediaURL: String
  let baseVersion: Int64
  let action: P2PPlaybackAction
  let positionMs: Double
  let expiresAt: Double
 }
 private var pending: Pending?

 mutating func begin(roomID: String,mediaURL: String,version: Int64,
                     action: P2PPlaybackAction,positionMs: Double,now: Double) {
  guard !roomID.isEmpty,!mediaURL.isEmpty,version>=0,
        now.isFinite,positionMs.isFinite,positionMs>=0 else {reset();return}
  pending=Pending(roomID:roomID,mediaURL:mediaURL,baseVersion:version,
                  action:action,positionMs:positionMs,expiresAt:now+2500)
 }

 mutating func reset() {pending=nil}

 // Defers local room-clock corrections, never ignores the actual Muse STATE.
 // After confirmation, defer only until the server's scheduled executeAt.
 // Rejections, a different command, new room/media and timeouts fall back.
 mutating func shouldDefer(now: Double,roomID: String,mediaURL: String,
                           version: Int64,state: String,positionMs: Double,
                           executeAtMs: Double,serverNowMs: Double?,
                           blocked: Bool) -> Bool {
  guard let hint=pending else{return false}
  guard !blocked,now.isFinite,now<=hint.expiresAt,
        roomID==hint.roomID,mediaURL==hint.mediaURL,
        version>=hint.baseVersion else {reset();return false}
  if version==hint.baseVersion {return true}
  // Two or more server revisions mean another command could have won.
  guard hint.baseVersion<Int64.max,version==hint.baseVersion+1,
        let serverNowMs,serverNowMs.isFinite,executeAtMs.isFinite else {reset();return false}
  let confirmed:Bool
  switch hint.action {
  case .play: confirmed=state=="playing"
  case .pause: confirmed=state=="paused"
  case .seek: confirmed=positionMs.isFinite && abs(positionMs-hint.positionMs)<=800
  }
  guard confirmed else {reset();return false}
  guard serverNowMs<executeAtMs else {reset();return false}
  return true
 }
}
