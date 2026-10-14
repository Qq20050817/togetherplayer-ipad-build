package dev.together.poc

import androidx.media3.common.PlaybackException
import org.junit.Assert.*
import org.junit.Test

class LocalContainerRecoveryTest {
 @Test fun malformedLocalFileCanTryIndependentDecoder() {
  val code=PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED
  assertTrue(LocalContainerRecovery.shouldTry(code,"content",false))
  assertTrue(LocalContainerRecovery.shouldTry(code,"file",false))
 }
 @Test fun noNetworkOrOtherCodecErrorsCanTriggerLocalFallback() {
  val malformed=PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED
  for(scheme in listOf("http","https","rtsp","smb",null))
   assertFalse("Network media should not be read twice: $scheme",
    LocalContainerRecovery.shouldTry(malformed,scheme,false))
  assertFalse(LocalContainerRecovery.shouldTry(
   PlaybackException.ERROR_CODE_DECODING_FAILED,"content",false))
  assertFalse(LocalContainerRecovery.shouldTry(malformed,"content",true))
 }
}
