package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.Format

/** A bounded hardware-output trial for already-failed ordinary HTTP HDR10 video. */
object HdrCompatibilityPolicy {
 fun useHardwareSurface(allowHttp:Boolean,format:Format?):Boolean {
  if(!allowHttp || format==null || format.sampleMimeType!="video/hevc" ||
   format.width !in 1..4096 || format.height !in 1..2160 ||
   format.colorInfo?.colorTransfer!=C.COLOR_TRANSFER_ST2084)return false
  // Matroska may expose valid Main10/PQ stream metadata before its codec
  // string is available. A missing codec string must not veto this bounded
  // post-failure HTTP hardware trial. An explicit non-Main10 profile still does.
  return HevcHdrRecovery.knownMain10Within4K(format) || format.codecs.isNullOrBlank()
 }
}
