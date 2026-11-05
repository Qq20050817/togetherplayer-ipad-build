package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.Format

/** A capability-query fallback, never a replacement for the actual playback Format. */
object HevcHdrRecovery {
 fun main10Probe(format:Format):Format? {
  if(format.sampleMimeType!="video/hevc" || format.width<=0 || format.height<=0 ||
   format.codecs?.matches(Regex("(?:hvc1|hev1)\\.2\\..+"))!=true ||
   format.colorInfo?.colorTransfer!=C.COLOR_TRANSFER_ST2084)return null
  // Media3 maps PQ Main10 to HEVCProfileMain10HDR10. Some vendor codecs only
  // advertise Main10. Query its compressed profile/level/size/rate separately;
  // keep CSD and every original HDR field when configuring the actual decoder.
  return format.buildUpon().setColorInfo(format.colorInfo!!.buildUpon()
   .setColorTransfer(C.COLOR_TRANSFER_SDR).build()).build()
 }
 fun accepts(exactSupport:Boolean,failedSoftware:Boolean,hardware:Boolean,
  probeAvailable:Boolean,main10Support:Boolean):Boolean = exactSupport ||
  (failedSoftware && hardware && probeAvailable && main10Support)
}
