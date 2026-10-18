package dev.together.poc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class P2PFastPathGateTest {
 private fun gate(): P2PFastPathGate = P2PFastPathGate().apply {
  attach("abcd1234", "host", "guest", 7)
 }
 private fun hint(roomID: String = "abcd1234", sender: String = "host",
  version: Long = 7, sequence: Long = 1, positionMs: Double = 500.0,
  issuedAtMs: Double = 100_000.0) = P2PControlHint(
  roomID,sender,version,sequence,P2PPlaybackAction.PAUSE,positionMs,issuedAtMs
 )
 @Test fun unverifiedChannelNeverAdmitted() {
  val g=gate()
  assertEquals(P2PAdmission.NO_VERIFIED_PEER,g.admit(hint(),101_000.0))
  g.verifyPeer(true)
  assertEquals(P2PAdmission.NO_VERIFIED_PEER,g.admit(hint(),101_000.0))
  g.setChannelAlive(true)
  assertEquals(P2PAdmission.ACCEPTED,g.admit(hint(),101_000.0))
  g.setChannelAlive(false)
  assertEquals(P2PAdmission.NO_VERIFIED_PEER,g.admit(hint(sequence=2),101_000.0))
 }
 @Test fun wrongRoomOrSenderRejected() {
  val g=gate();g.verifyPeer(true);g.setChannelAlive(true)
  assertEquals(P2PAdmission.ROOM_MISMATCH,g.admit(hint(roomID="other"),101_000.0))
  assertEquals(P2PAdmission.WRONG_SENDER,g.admit(hint(sender="intruder"),101_000.0))
  assertEquals(P2PAdmission.ACCEPTED,g.admit(hint(),101_000.0))
 }
 @Test fun orderedReplayGuardAndServerVersion() {
  val g=gate();g.verifyPeer(true);g.setChannelAlive(true)
  assertEquals(P2PAdmission.ACCEPTED,g.admit(hint(),101_000.0))
  assertEquals(P2PAdmission.STALE_SEQUENCE,g.admit(hint(),101_000.0))
  assertEquals(P2PAdmission.INVALID_COMMAND,g.admit(hint(sequence=2,positionMs=-1.0),101_000.0))
  assertEquals(P2PAdmission.STALE_VERSION,g.admit(hint(sequence=2,version=6),101_000.0))
  g.serverState(8)
  assertEquals(P2PAdmission.STALE_VERSION,g.admit(hint(sequence=2),101_000.0))
  assertEquals(P2PAdmission.ACCEPTED,g.admit(hint(sequence=2,version=8),101_000.0))
 }
 @Test fun rejectExpiredOrFutureCommands() {
  val g=gate();g.verifyPeer(true);g.setChannelAlive(true)
  assertEquals(P2PAdmission.EXPIRED,g.admit(hint(),106_000.0))
  assertEquals(P2PAdmission.EXPIRED,g.admit(hint(),97_000.0))
  assertEquals(P2PAdmission.ACCEPTED,g.admit(hint(),102_000.0))
 }
 @Test fun roomSwitchForcesReverification() {
  val g=gate();g.verifyPeer(true);g.setChannelAlive(true)
  assertEquals(P2PAdmission.ACCEPTED,g.admit(hint(),100_000.0))
  g.attach("room9999","newhost","guest",1)
  assertFalse(g.peerVerified)
  assertEquals(0L,g.lastSequence)
  assertEquals(P2PAdmission.NO_VERIFIED_PEER,g.admit(hint(roomID="room9999",sender="newhost",version=1),100_000.0))
 }
 @Test fun hostCannotApplyOwnFastHint() {
  val g=P2PFastPathGate()
  g.attach("abcd1234","host","host",7);g.verifyPeer(true);g.setChannelAlive(true)
  assertEquals(P2PAdmission.WRONG_SENDER,g.admit(hint(),100_000.0))
 }
}
