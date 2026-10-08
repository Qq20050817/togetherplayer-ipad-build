package dev.together.poc
import org.junit.Assert.assertEquals
import org.junit.Test
class DanmakuSpeedTest {
 @Test fun speedChangesOnlyDanmakuTravelDuration() {
  assertEquals(20000L,DanmakuSpeed.duration(10000,0.5f))
  assertEquals(5000L,DanmakuSpeed.duration(10000,2f))
  assertEquals(10000L,DanmakuSpeed.duration(5000,0.5f))
  assertEquals(10000L,DanmakuSpeed.duration(10000,Float.NaN))
 }
}
