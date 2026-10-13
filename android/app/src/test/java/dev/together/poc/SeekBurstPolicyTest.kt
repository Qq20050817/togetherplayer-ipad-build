package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class SeekBurstPolicyTest {
 @Test fun repeatedTenSecondTapsAccumulateBeforeDecoderCatchesUp() {
  val taps=SeekTapAccumulator()
  assertEquals(10_000.0,taps.next(0.0,10_000.0,100.0,100_000.0,0.0),0.001)
  assertEquals(20_000.0,taps.next(0.0,10_000.0,200.0,100_000.0,0.0),0.001)
  assertEquals(30_000.0,taps.next(0.0,10_000.0,300.0,100_000.0,0.0),0.001)
  assertEquals(20_000.0,taps.next(0.0,-10_000.0,400.0,100_000.0,0.0),0.001)
  assertEquals(35_000.0,taps.next(25_000.0,10_000.0,2000.0,100_000.0,0.0),0.001)
 }
 @Test fun boundsAndNewMovieResetAreSafe() {
  val taps=SeekTapAccumulator()
  assertEquals(0.0,taps.next(2000.0,-10_000.0,100.0,60_000.0,0.0),0.001)
  assertEquals(60_000.0,taps.next(0.0,100_000.0,200.0,60_000.0,0.0),0.001)
  taps.reset()
  assertEquals(10_000.0,taps.next(0.0,10_000.0,300.0,90_000.0,0.0),0.001)
  assertEquals(80_000.0,taps.next(0.0,100_000.0,400.0,100_000.0,20_000.0),0.001)
 }
}