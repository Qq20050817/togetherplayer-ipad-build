package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class HdrFrameProgressWatchdogTest {
 @Test fun detectsOnlyContinuousTenSecondFreezeDuringActivePlayback() {
  val guard=HdrFrameProgressWatchdog()
  assertFalse(guard.isFrozen(1_000L,20L,true))
  assertFalse(guard.isFrozen(10_999L,20L,true))
  assertTrue(guard.isFrozen(11_000L,20L,true))
  assertFalse(guard.isFrozen(11_001L,21L,true))
  assertFalse(guard.isFrozen(20_500L,21L,true))
  assertTrue(guard.isFrozen(21_001L,21L,true))
 }
 @Test fun pausedOrBufferedPlaybackCannotQualifyAsFrozen() {
  val guard=HdrFrameProgressWatchdog()
  assertFalse(guard.isFrozen(1L,0L,true))
  assertFalse(guard.isFrozen(20_000L,0L,false))
  assertFalse(guard.isFrozen(20_001L,0L,true))
  assertFalse(guard.isFrozen(21_000L,null,true))
  assertFalse(guard.isFrozen(21_001L,0L,true))
  assertFalse(guard.isFrozen(30_999L,0L,true))
 }
 @Test fun sourceClockResetCannotUsePreviousFreezeWindow() {
  val guard=HdrFrameProgressWatchdog()
  assertFalse(guard.isFrozen(8_000L,8L,true))
  assertFalse(guard.isFrozen(1L,0L,true))
  assertFalse(guard.isFrozen(9_999L,0L,true))
  assertFalse(guard.isFrozen(10_000L,1L,true))
 }
}
