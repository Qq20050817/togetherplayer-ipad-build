package dev.together.poc

// Independent P2P transport policy experiment. The Muse room and server ACK
// remain authoritative. This type does not play media or send any messages.
enum class P2PPlaybackAction { PLAY, PAUSE, SEEK }
enum class P2PAdmission {
 ACCEPTED, NO_VERIFIED_PEER, ROOM_MISMATCH, WRONG_SENDER,
 INVALID_COMMAND, STALE_SEQUENCE, STALE_VERSION, EXPIRED
}
data class P2PControlHint(
 val roomID: String,
 val senderUserID: String,
 val roomVersion: Long,
 val sequence: Long,
 val action: P2PPlaybackAction,
 val positionMs: Double,
 val issuedAtMs: Double
)

// Fail closed: a WebRTC connection is NOT sufficient authorization.
// Peer identity must be verified against an authenticated Muse room roster.
class P2PFastPathGate {
 var roomID: String? = null
  private set
 var hostUserID: String? = null
  private set
 var localUserID: String? = null
  private set
 var serverVersion = 0L
  private set
 var lastSequence = 0L
  private set
 var peerVerified = false
  private set
 var channelAlive = false
  private set

 fun attach(roomID: String, hostUserID: String, localUserID: String, serverVersion: Long) {
  if (roomID.isBlank() || hostUserID.isBlank() || localUserID.isBlank() || serverVersion < 0) {
   reset(); return
  }
  this.roomID=roomID
  this.hostUserID=hostUserID
  this.localUserID=localUserID
  this.serverVersion=serverVersion
  lastSequence=0
  peerVerified=false
  channelAlive=false
 }
 fun verifyPeer(fromAuthoritativeRoster: Boolean) {
  peerVerified=fromAuthoritativeRoster && roomID!=null && hostUserID!=null
 }
 fun setChannelAlive(alive: Boolean) {channelAlive=alive}
 fun serverState(version: Long) {if(version>serverVersion) serverVersion=version}
 fun reset() {
  roomID=null;hostUserID=null;localUserID=null
  serverVersion=0;lastSequence=0;peerVerified=false;channelAlive=false
 }
 fun admit(hint: P2PControlHint, nowMs: Double): P2PAdmission {
  if(!peerVerified || !channelAlive) return P2PAdmission.NO_VERIFIED_PEER
  if(hint.roomID!=roomID) return P2PAdmission.ROOM_MISMATCH
  if(hint.senderUserID!=hostUserID || localUserID==hostUserID) return P2PAdmission.WRONG_SENDER
  if(hint.sequence<=0 || !hint.positionMs.isFinite() || hint.positionMs<0 || hint.positionMs>86_400_000) return P2PAdmission.INVALID_COMMAND
  if(hint.sequence<=lastSequence) return P2PAdmission.STALE_SEQUENCE
  if(hint.roomVersion!=serverVersion) return P2PAdmission.STALE_VERSION
  // Only admit after clock sync; do not rely on this guard without
  // verifying sender identity and bounding cross-device clock skew.
  if(!nowMs.isFinite() || !hint.issuedAtMs.isFinite()
     || nowMs-hint.issuedAtMs < -2_000 || nowMs-hint.issuedAtMs>5_000) return P2PAdmission.EXPIRED
  lastSequence=hint.sequence
  return P2PAdmission.ACCEPTED
 }
}
