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
 @Test fun queryPreservesCompressedRequirementsAndNeverMutatesActualHdrFormat() {
  val actual=movie();val original=actual.buildUpon().build()
  val probe=HevcHdrRecovery.main10Probe(actual)!!
  assertEquals(original,actual)
  assertEquals(C.COLOR_TRANSFER_ST2084,actual.colorInfo!!.colorTransfer)
  assertEquals(C.COLOR_TRANSFER_SDR,probe.colorInfo!!.colorTransfer)
  assertEquals(actual.codecs,probe.codecs);assertEquals(actual.width,probe.width)
  assertEquals(actual.height,probe.height);assertEquals(actual.frameRate,probe.frameRate,0f)
  assertEquals(actual.colorInfo!!.colorSpace,probe.colorInfo!!.colorSpace)
  assertArrayEquals(actual.colorInfo!!.hdrStaticInfo,probe.colorInfo!!.hdrStaticInfo)
  assertArrayEquals(actual.initializationData[0],probe.initializationData[0])
  assertEquals(android.media.MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10,
   androidx.media3.exoplayer.mediacodec.MediaCodecUtil.getCodecProfileAndLevel(actual)!!.first.toInt())
  assertEquals(android.media.MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10,
   androidx.media3.exoplayer.mediacodec.MediaCodecUtil.getCodecProfileAndLevel(probe)!!.first.toInt())
 }
 @Test fun ordinarySdrOtherProfilesUnknownDimensionsAndHlgNeverUseProbe() {
  val f=movie()
  assertNull(HevcHdrRecovery.main10Probe(f.buildUpon().setSampleMimeType("video/avc").build()))
  assertNull(HevcHdrRecovery.main10Probe(f.buildUpon().setCodecs("hvc1.1.4.L150.90").build()))
  assertNull(HevcHdrRecovery.main10Probe(f.buildUpon().setCodecs(null).build()))
  assertNull(HevcHdrRecovery.main10Probe(f.buildUpon().setWidth(-1).build()))
  for(transfer in listOf(C.COLOR_TRANSFER_SDR,C.COLOR_TRANSFER_HLG))
   assertNull(HevcHdrRecovery.main10Probe(f.buildUpon().setColorInfo(f.colorInfo!!.buildUpon().setColorTransfer(transfer).build()).build()))
 }
}
