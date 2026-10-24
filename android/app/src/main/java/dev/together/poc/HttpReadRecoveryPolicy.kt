package dev.together.poc

import androidx.media3.common.PlaybackException

/**
 * Retry only transient HTTP source failures. 2008 can occur when a Range
 * request points beyond the currently advertised resource length, including
 * during router reboots or after a source reconnect.
 *
 * Local SAF/file sources are excluded by MainActivity's httpHealth check.
 */
internal object HttpReadRecoveryPolicy {
 fun shouldRetry(errorCode:Int,httpStatus:Int?):Boolean = when(errorCode) {
  PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
  PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
  PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE -> true
  PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS -> httpStatus in setOf(429,500,502,503,504)
  else -> false
 }

 /** Never seek beyond a known end of file. Unknown durations keep room time. */
 fun safeSeekMs(positionMs:Long,durationMs:Long):Long {
  val requested=positionMs.coerceAtLeast(0L)
  if(durationMs<=0L || durationMs==androidx.media3.common.C.TIME_UNSET)return requested
  return requested.coerceAtMost((durationMs-1_000L).coerceAtLeast(0L))
 }

 fun retryDelayMs(attempt:Int):Long=if(attempt<=0)1_500L else 4_000L

 fun status(errorCode:Int,httpStatus:Int?):String=when {
  errorCode==PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE -> "HTTP 读取位置越界"
  httpStatus!=null -> "HTTP $httpStatus 暂不可用"
  else -> "HTTP 网络暂时中断"
 }
}
