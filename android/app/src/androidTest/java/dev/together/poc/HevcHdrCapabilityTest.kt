package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HevcHdrCapabilityTest {
 private fun movie()=Format.Builder().setSampleMimeType("video/hevc")
  .setCodecs("hvc1.2.4.L150.90").setWidth(3840).setHeight(1600).setFrameRate(24f)
  .setColorInfo(ColorInfo.Builder().setColorSpace(C.COLOR_SPACE_BT2020)
   .setColorTransfer(C.COLOR_TRANSFER_ST2084).setColorRange(C.COLOR_RANGE_LIMITED)
   .setHdrStaticInfo(byteArrayOf(1,2,3)).build())
  .setInitializationData(listOf(byteArrayOf(4,5,6))).build()
 @Test fun runtimeTrialKeepsOriginalHdrAndCompressedFormatUnchanged() {
  val actual=movie();val original=actual.buildUpon().build()
  assertTrue(HevcHdrRecovery.knownMain10Within4K(actual))
  assertEquals(original,actual)
  assertEquals(C.COLOR_TRANSFER_ST2084,actual.colorInfo!!.colorTransfer)
  assertArrayEquals(byteArrayOf(1,2,3),actual.colorInfo!!.hdrStaticInfo)
  assertArrayEquals(byteArrayOf(4,5,6),actual.initializationData[0])
  assertEquals(android.media.MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10,
   androidx.media3.exoplayer.mediacodec.MediaCodecUtil.getCodecProfileAndLevel(actual)!!.first.toInt())
 }
 @Test fun rejectsUnknownProfileSizeAnd8KButDoesNotDependOnMissingPqMetadata() {
  val f=movie()
  assertFalse(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setSampleMimeType("video/avc").build()))
  assertFalse(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setCodecs("hvc1.1.4.L150.90").build()))
  assertFalse(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setCodecs(null).build()))
  assertFalse(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setWidth(-1).build()))
  assertFalse(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setWidth(7680).build()))
  assertTrue(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setColorInfo(null).build()))
  for(transfer in listOf(C.COLOR_TRANSFER_SDR,C.COLOR_TRANSFER_HLG))
   assertTrue(HevcHdrRecovery.knownMain10Within4K(f.buildUpon().setColorInfo(f.colorInfo!!.buildUpon().setColorTransfer(transfer).build()).build()))
 }
}
