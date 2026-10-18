package dev.together.poc

import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test

class HttpPlaybackHealthTest {
 @Test fun onlyHttpShowsThroughputAndSwitchingToLocalClearsOldSpeed(){
  val health=HttpPlaybackHealth()
  health.reset("https://example.invalid/movie.mkv?expires=123&sig=private")
  health.onBandwidthEstimate(1000,1_000_000,16_000_000)
  assertTrue(health.display(13_100).contains("16.0 Mbps"))
  assertTrue(health.display(13_100).contains("已缓冲 13s"))
  assertFalse(health.display(13_100).contains("sig="))
  health.reset("content://media/external/video/1")
  assertEquals("",health.display(50_000))
  assertNull(health.speedMbps)
 }
 @Test fun ignoredSamplesCannotShowFalseSpeed(){
  val h=HttpPlaybackHealth()
  h.reset("http://example.invalid/movie.mkv")
  h.onBandwidthEstimate(0,100_000,0)
  h.onBandwidthEstimate(500,10_000,0)
  assertNull(h.speedMbps)
  assertTrue(h.display(0).contains("速度待测"))
  h.onBandwidthEstimate(1000,125_000,-1)
  assertEquals(1.0,h.speedMbps!!,0.01)
 }
 @Test fun onlyRealRebuffersAfterReadyIncreaseRecoveryReserve(){
  val h=HttpPlaybackHealth()
  h.reset("https://example.invalid/movie.mkv")
  h.onPlaybackState(Player.STATE_BUFFERING,true,1000)
  h.onPlaybackState(Player.STATE_READY,false,2000)
  h.onPlaybackState(Player.STATE_BUFFERING,false,3000)
  assertEquals(0,h.stalls)
  h.onPlaybackState(Player.STATE_READY,true,4000)
  h.onPlaybackState(Player.STATE_BUFFERING,true,5000)
  assertEquals(1,h.stalls)
  assertEquals(12000,h.resumeReserveMs())
  h.onPlaybackState(Player.STATE_BUFFERING,true,6000)
  assertEquals(1,h.stalls)
  h.onPlaybackState(Player.STATE_READY,true,7000)
  h.onPlaybackState(Player.STATE_BUFFERING,true,8000)
  assertEquals(16000,h.resumeReserveMs())
  h.onPlaybackState(Player.STATE_READY,true,9000)
  h.onPlaybackState(Player.STATE_BUFFERING,true,10000)
  assertEquals(20000,h.resumeReserveMs())
  h.reset("https://example.invalid/another.mp4")
  assertEquals(0,h.stalls)
 }
 @Test fun remainingMediaIsClampedForShortTail(){
  val h=HttpPlaybackHealth()
  h.setRemaining(60_000,55_500)
  assertEquals(4_500,h.remainingMs)
  h.setRemaining(0,50_000)
  assertEquals(Long.MAX_VALUE,h.remainingMs)
 }
}
