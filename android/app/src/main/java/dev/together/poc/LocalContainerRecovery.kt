package dev.together.poc

import androidx.media3.common.PlaybackException

/**
 * The HEVC-decoder recovery path does not run when ExoPlayer fails before
 * identifying tracks. Only retry malformed LOCAL containers in LibVLC.
 * Network/Baidu playback is deliberately excluded to avoid extra downloads.
 */
internal object LocalContainerRecovery {
 fun shouldTry(errorCode:Int,scheme:String?,alreadyCompatible:Boolean):Boolean =
  !alreadyCompatible &&
  errorCode==PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED &&
  (scheme=="content" || scheme=="file")
}
