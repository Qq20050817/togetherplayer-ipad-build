package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
class VideoDecoderRecoveryTest {
 @Test fun runtimeRecoveryExcludesFailuresAndStopsAfterTwoAttempts() {
  val p=VideoDecoderRecovery();p.beginSource("content://movie/1")
  assertEquals("alternate",p.recover("video/hevc","hardware",listOf("hardware","alternate","software")))
  assertFalse(p.allowed("hardware"));assertTrue(p.allowed("alternate"))
  assertEquals("software",p.recover("video/hevc","alternate",listOf("hardware","alternate","software")))
  assertNull(p.recover("video/hevc","software",listOf("fourth")))
  p.beginSource("content://movie/1");assertFalse(p.allowed("hardware"))
  p.beginSource("content://movie/2");assertTrue(p.allowed("hardware"))
 }
 @Test fun noRetryForIoAudioUnknownCodecOrMissingAlternative() {
  val p=VideoDecoderRecovery();p.beginSource("file://movie")
  assertNull(p.recover("audio/aac","audio",listOf("other")))
  assertNull(p.recover("video/avc","video",listOf("other")))
  assertNull(p.recover("video/hevc",null,listOf("other")))
  assertNull(p.recover("video/hevc","hardware",listOf("hardware")))
  assertTrue(p.allowed("hardware"))
  assertEquals("other",p.recover("video/hevc","hardware",listOf("other")))
  assertNull(p.recover("video/hevc","hardware",listOf("other","third")))
 }
}
