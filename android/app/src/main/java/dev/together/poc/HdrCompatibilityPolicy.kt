package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.Format

/** A bounded hardware-output trial for already-failed ordinary HTTP HDR10 video. */
object HdrCompatibilityPolicy {
 fun useHardwareSurface(allowHttp:Boolean,format:Format?):Boolean {
  if(!allowHttp || format==null || format.sampleMimeType!="video/hevc" ||
   format.width !in 1..4096 || format.height !in 1..2160)return false
  val main10=HevcHdrRecovery.knownMain10Within4K(format)
  // Some Matroska/HTTP extractor paths retain the Main10 codec profile but
  // omit the transfer marker. After every system HEVC decoder has failed,
  // trial the original bitstream through VLC hardware + SurfaceView.
  // Explicit SDR/HLG transfers must never be re-labelled as PQ.
  return when(format.colorInfo?.colorTransfer){
   C.COLOR_TRANSFER_ST2084 -> main10 || format.codecs.isNullOrBlank()
   null,Format.NO_VALUE -> main10
   else -> false
  }
 }
}
