package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.Format

/** A bounded hardware-output trial for already-failed ordinary HTTP HDR10 video. */
object HdrCompatibilityPolicy {
 fun useHardwareSurface(allowHttp:Boolean,format:Format?):Boolean =
  allowHttp && format!=null && HevcHdrRecovery.knownMain10Within4K(format) &&
   format.colorInfo?.colorTransfer==C.COLOR_TRANSFER_ST2084
}
