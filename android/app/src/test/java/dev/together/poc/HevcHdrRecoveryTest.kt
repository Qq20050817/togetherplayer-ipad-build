package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class HevcHdrRecoveryTest {
 @Test fun exactSupportKeepsExistingRecoveryForEveryDecoder() {
  assertTrue(HevcHdrRecovery.accepts(true,false,false,false,false))
 }
 @Test fun runtimeTrialRequiresObservedSoftwareFailureHardwareHttpAndKnownMain10() {
  assertTrue(HevcHdrRecovery.accepts(false,true,true,true,true))
  assertFalse(HevcHdrRecovery.accepts(false,false,true,true,true))
  assertFalse(HevcHdrRecovery.accepts(false,true,false,true,true))
  assertFalse(HevcHdrRecovery.accepts(false,true,true,false,true))
  assertFalse(HevcHdrRecovery.accepts(false,true,true,true,false))
 }
 @Test fun hdrTrialUsesExistingExclusionAndPerSourceRetryBudget() {
  val r=VideoDecoderRecovery();r.beginSource("https://example.org/synthetic.mkv")
  assertFalse(r.softwareFailureSeen);r.noteSoftwareFailure();assertTrue(r.softwareFailureSeen)
  assertEquals("vendor",r.recover("video/hevc","software",listOf("vendor")))
  assertFalse(r.allowed("software"))
  assertNull(r.recover("video/hevc","vendor",listOf("software")))
  assertTrue(r.allowed("vendor"))
  assertEquals("vendor-second",r.recover("video/hevc","vendor",listOf("vendor-second")))
  assertNull(r.recover("video/hevc","vendor-second",listOf("third")))
  r.beginSource("https://example.org/another.mkv");assertFalse(r.softwareFailureSeen)
 }
}
