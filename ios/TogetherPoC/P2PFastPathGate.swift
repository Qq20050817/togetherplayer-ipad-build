import Foundation

// Experimental P2P fast-path admission only. The existing Muse room remains
// authoritative: this policy does not mutate Room, send commands, or play media.
enum P2PPlaybackAction: String, Equatable {
 case play = "PLAY"
 case pause = "PAUSE"
 case seek = "SEEK"
}

struct P2PControlHint: Equatable {
 let roomID: String
 let senderUserID: String
 let roomVersion: Int64
 let sequence: Int64
 let action: P2PPlaybackAction
 let positionMs: Double
 let issuedAtMs: Double
}

enum P2PAdmission: Equatable {
 case accepted
 case noVerifiedPeer
 case roomMismatch
 case wrongSender
 case invalidCommand
 case staleSequence
 case staleVersion
 case expired
}

// Deny-by-default guard shared across the two experimental client branches.
// "authenticated" must only be set after the peer is tied to the server's
// authorized room roster. A browser P2P success signal alone is insufficient.
struct P2PFastPathGate {
 private(set) var roomID: String?
 private(set) var hostUserID: String?
 private(set) var localUserID: String?
 private(set) var serverVersion: Int64 = 0
 private(set) var lastSequence: Int64 = 0
 private(set) var peerVerified = false
 private(set) var channelAlive = false

 mutating func attach(roomID: String, hostUserID: String, localUserID: String, serverVersion: Int64) {
  guard !roomID.isEmpty, !hostUserID.isEmpty, !localUserID.isEmpty, serverVersion >= 0 else {
   reset(); return
  }
  self.roomID = roomID; self.hostUserID = hostUserID; self.localUserID = localUserID
  self.serverVersion = serverVersion
  self.lastSequence = 0
  self.peerVerified = false
  self.channelAlive = false
 }

 mutating func verifyPeer(fromAuthoritativeRoster verified: Bool) {
  peerVerified = verified && roomID != nil && hostUserID != nil
 }

 mutating func setChannelAlive(_ alive: Bool) { channelAlive = alive }

 mutating func serverState(version: Int64) {
  if version > serverVersion { serverVersion = version }
 }

 mutating func reset() {
  roomID = nil; hostUserID = nil; localUserID = nil
  serverVersion = 0; lastSequence = 0
  peerVerified = false; channelAlive = false
 }

 mutating func admit(_ hint: P2PControlHint, nowMs: Double) -> P2PAdmission {
  guard peerVerified, channelAlive else { return .noVerifiedPeer }
  guard let roomID, hint.roomID == roomID else { return .roomMismatch }
  // The real room owner is the only source of speculative play commands.
  guard let hostUserID, hint.senderUserID == hostUserID, localUserID != hostUserID else { return .wrongSender }
  guard hint.sequence > 0, hint.positionMs.isFinite, hint.positionMs >= 0, hint.positionMs <= 86_400_000 else { return .invalidCommand }
  guard hint.sequence > lastSequence else { return .staleSequence }
  guard hint.roomVersion == serverVersion else { return .staleVersion }
  // Both peers must have sufficiently synchronized wall clocks before
  // enabling admission; otherwise remain on Muse authoritative updates.
  guard nowMs.isFinite, hint.issuedAtMs.isFinite,
        nowMs - hint.issuedAtMs >= -2_000, nowMs - hint.issuedAtMs <= 5_000 else { return .expired }
  lastSequence = hint.sequence
  return .accepted
 }
}
