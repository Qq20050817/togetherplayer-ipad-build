package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import org.junit.Assert.*
import org.junit.Test

class HdrCompatibilityPolicyTest {
 private fun movie()=Format.Builder().setSampleMimeType("video/hevc")
  .setCodecs("hvc1.2.4.L150.90").setWidth(3840).setHeight(1600)
  .setColorInfo(ColorInfo.Builder().setColorSpace(C.COLOR_SPACE_BT2020)
   .setColorTransfer(C.COLOR_TRANSFER_ST2084).setHdrStaticInfo(byteArrayOf(1,2,3)).build())
  .setInitializationData(listOf(byteArrayOf(4,5,6))).build()

 @Test fun onlyFailedOrdinaryHttpMain10Hdr10OffersHardwareSurface() {
  val f=movie()
  assertTrue(HdrCompatibilityPolicy.useHardwareSurface(true,f))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(false,f))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(true,null))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setColorInfo(null).build()))
  assertTrue("Missing RFC6381 metadata must not veto known PQ HEVC recovery",
   HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setCodecs(null).build()))
  assertTrue(HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setCodecs("").build()))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setCodecs("hvc1.1.4.L150.90").build()))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setSampleMimeType("video/avc").setCodecs(null).build()))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setWidth(7680).build()))
  assertFalse(HdrCompatibilityPolicy.useHardwareSurface(true,f.buildUpon().setColorInfo(
   f.colorInfo!!.buildUpon().setColorTransfer(C.COLOR_TRANSFER_SDR).build()).build()))
  // This policy must not rewrite compressed data or HDR metadata.
  assertEquals(C.COLOR_TRANSFER_ST2084,f.colorInfo!!.colorTransfer)
  assertArrayEquals(byteArrayOf(1,2,3),f.colorInfo!!.hdrStaticInfo)
  assertArrayEquals(byteArrayOf(4,5,6),f.initializationData[0])
 }
}
