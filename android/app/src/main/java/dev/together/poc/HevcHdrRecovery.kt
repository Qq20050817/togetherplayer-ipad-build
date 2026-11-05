package dev.together.poc

import androidx.media3.common.Format

/** Bounded runtime trial when reported capabilities rejected every decoder. */
object HevcHdrRecovery {
 fun knownMain10Within4K(format:Format):Boolean = format.sampleMimeType=="video/hevc" &&
  format.width in 1..4096 && format.height in 1..2160 &&
  format.codecs?.matches(Regex("(?:hvc1|hev1)\\.2\\..+"))==true
 // Reported support remains diagnostic evidence. It cannot reject the bounded
 // runtime hardware trial again: that gate caused the real device to retry
 // only software. Actual codec configuration decides whether the trial works.
 // Never replace the actual Format or manufacture HDR metadata.
 fun accepts(exactSupport:Boolean,softwareFailureSeen:Boolean,hardware:Boolean,
  ordinaryHttp:Boolean,knownMain10:Boolean):Boolean = exactSupport ||
  (softwareFailureSeen && hardware && ordinaryHttp && knownMain10)
}
