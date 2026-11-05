package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class HevcHdrRecoveryTest {
 @Test fun exactSupportKeepsExistingRecoveryForEveryDecoder() {
  assertTrue(HevcHdrRecovery.accepts(true,false,false,false,false))
 }
 @Test fun hdrFlagFallbackRequiresFailedSoftwareAndSupportedHardwareMain10() {
  assertTrue(HevcHdrRecovery.accepts(false,true,true,true,true))
  assertFalse(HevcHdrRecovery.accepts(false,false,true,true,true))
  assertFalse(HevcHdrRecovery.accepts(false,true,false,true,true))
  assertFalse(HevcHdrRecovery.accepts(false,true,true,false,true))
  assertFalse(HevcHdrRecovery.accepts(false,true,true,true,false))
 }
 @Test fun hdrTrialUsesExistingExclusionAndPerSourceRetryBudget() {
  val r=VideoDecoderRecovery();r.beginSource("https://example.org/synthetic.mkv")
  assertEquals("vendor",r.recover("video/hevc","software",listOf("vendor")))
  assertFalse(r.allowed("software"))
  assertNull(r.recover("video/hevc","vendor",listOf("software")))
  assertTrue(r.allowed("vendor"))
 }
}
