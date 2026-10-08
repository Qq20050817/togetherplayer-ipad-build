package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class RecoveryBufferPolicyTest {
 @Test fun shortBufferDoesNotResumeRoomButFullReserveDoes() {
  assertFalse(RecoveryBufferPolicy.ready(true,3000,10000,100000,true))
  assertTrue(RecoveryBufferPolicy.ready(true,12000,10000,100000,true))
 }
 @Test fun tailCanFinishWithoutImpossibleTwelveSecondReserve() {
  assertTrue(RecoveryBufferPolicy.ready(true,1950,98000,100000,true))
  assertFalse(RecoveryBufferPolicy.ready(true,1000,98000,100000,true))
 }
 @Test fun preparationAndUnknownDurationCannotBypassReserve() {
  assertFalse(RecoveryBufferPolicy.ready(false,60000,0,100000,true))
  assertFalse(RecoveryBufferPolicy.ready(true,3000,0,-1,true))
 }
 @Test fun ordinaryPlayingAndManualPauseDoNotAcquireRecoveryGate() {
  assertTrue(RecoveryBufferPolicy.ready(true,1000,0,100000,false))
 }
}
