package dev.together.poc

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackTapRecoveryPolicyTest {
 private fun action(room:String,state:Int,error:Boolean=false,waiting:Boolean=false,stalled:Boolean=false)=
  PlaybackTapRecoveryPolicy.decide(room,state,error,waiting,stalled)

 @Test fun HTTPConnectionTimeoutTapRebuildsOnlyThisPhoneWithoutPausingRoom() {
  assertEquals(PlaybackTapRecoveryPolicy.Action.RELOAD_LOCAL_PLAYER,action("playing",Player.STATE_IDLE,true))
 }
 @Test fun clickingWhileBufferedButStuckRetriesLocalPlayer() {
  assertEquals(PlaybackTapRecoveryPolicy.Action.RELOAD_LOCAL_PLAYER,action("playing",Player.STATE_BUFFERING))
 }
 @Test fun ordinaryPlayingTapStillPausesRoom() {
  assertEquals(PlaybackTapRecoveryPolicy.Action.TOGGLE_ROOM,action("playing",Player.STATE_READY))
 }
 @Test fun pausedRoomWithDeadPlayerReloadsThenRequestsPlayback() {
  assertEquals(PlaybackTapRecoveryPolicy.Action.RELOAD_AND_PLAY_ROOM,action("paused",Player.STATE_IDLE,true))
 }
 @Test fun waitForPeerPauseAllowsReloadWithoutPrematureGlobalResume() {
  assertEquals(PlaybackTapRecoveryPolicy.Action.RELOAD_LOCAL_PLAYER,action("paused",Player.STATE_BUFFERING,waiting=true))
 }
 @Test fun healthyStallWakeDoesNotReopenSource() {
  assertEquals(PlaybackTapRecoveryPolicy.Action.WAKE_PLAYER,action("playing",Player.STATE_READY,stalled=true))
 }
 @Test fun reconnectReloadsErroredPlayerEvenWhenRoomUrlIsUnchanged() {
  assertEquals(true,PlaybackTapRecoveryPolicy.needsReloadAfterWelcome(Player.STATE_IDLE,true))
  assertEquals(true,PlaybackTapRecoveryPolicy.needsReloadAfterWelcome(Player.STATE_READY,true))
  assertEquals(true,PlaybackTapRecoveryPolicy.needsReloadAfterWelcome(Player.STATE_IDLE,false))
  assertEquals(false,PlaybackTapRecoveryPolicy.needsReloadAfterWelcome(Player.STATE_READY,false))
 }
}
