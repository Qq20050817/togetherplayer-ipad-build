package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class VideoRotationTest {
 @Test fun turnsCycleAndSwapOnlyOnQuarterTurns() {
  var turns=0
  for(expected in listOf(90,180,270,0)){turns=VideoRotation.next(turns);assertEquals(expected,VideoRotation.degrees(turns))}
  assertEquals(1080 to 1920,VideoRotation.childSize(1920,1080,1))
  assertEquals(1920 to 1080,VideoRotation.childSize(1920,1080,2))
 }
}
