package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HttpReadRecoveryPolicyTest {
 @Test fun rangeReadOutOfBoundsIsRetryable() {
  assertTrue(HttpReadRecoveryPolicy.shouldRetry(
   PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,null))
 }

 @Test fun networkDisconnectAndTimeoutKeepTheirExistingRecovery() {
  assertTrue(HttpReadRecoveryPolicy.shouldRetry(
   PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,null))
  assertTrue(HttpReadRecoveryPolicy.shouldRetry(
   PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,null))
 }

 @Test fun temporaryGatewayFailuresRetryButPermanentStatusesDoNot() {
  for(code in listOf(429,500,502,503,504)){
   assertTrue(HttpReadRecoveryPolicy.shouldRetry(PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,code))
  }
  for(code in listOf(401,403,404,416)){
   assertFalse(HttpReadRecoveryPolicy.shouldRetry(PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,code))
  }
 }

 @Test fun unrelatedDecodeOrFileErrorsCannotStartHttpRetry() {
  assertFalse(HttpReadRecoveryPolicy.shouldRetry(PlaybackException.ERROR_CODE_DECODING_FAILED,null))
  assertFalse(HttpReadRecoveryPolicy.shouldRetry(PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,null))
  assertFalse(HttpReadRecoveryPolicy.shouldRetry(PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,null))
 }

 @Test fun knownDurationClampsOvershootButKeepsValidRoomPosition() {
  assertEquals(30_000L,HttpReadRecoveryPolicy.safeSeekMs(30_000L,90_000L))
  assertEquals(89_000L,HttpReadRecoveryPolicy.safeSeekMs(900_000L,90_000L))
  assertEquals(0L,HttpReadRecoveryPolicy.safeSeekMs(-500L,90_000L))
  assertEquals(0L,HttpReadRecoveryPolicy.safeSeekMs(500L,700L))
 }

 @Test fun unknownDurationDoesNotResetRoomPosition() {
  assertEquals(30_000L,HttpReadRecoveryPolicy.safeSeekMs(30_000L,C.TIME_UNSET))
  assertEquals(30_000L,HttpReadRecoveryPolicy.safeSeekMs(30_000L,-1L))
 }

 @Test fun retriesAreBoundedAndLabelTheActualFailure() {
  assertEquals(1_500L,HttpReadRecoveryPolicy.retryDelayMs(0))
  assertEquals(4_000L,HttpReadRecoveryPolicy.retryDelayMs(1))
  assertEquals("HTTP 读取位置越界",HttpReadRecoveryPolicy.status(
   PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,null))
  assertEquals("HTTP 503 暂不可用",HttpReadRecoveryPolicy.status(
   PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,503))
 }
}
