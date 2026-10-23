package dev.together.poc

import androidx.media3.common.Player

/**
 * A user tapping the main playback button while the player cannot render frames
 * is asking to recover that device. Avoid turning the whole shared room PAUSED.
 */
internal object PlaybackTapRecoveryPolicy {
 enum class Action { TOGGLE_ROOM, RELOAD_LOCAL_PLAYER, RELOAD_AND_PLAY_ROOM, WAKE_PLAYER }

 fun decide(
  roomState:String,
  playerState:Int,
  hasPlayerError:Boolean,
  waitingForBuffer:Boolean,
  stalled:Boolean
 ):Action {
  val broken=hasPlayerError || playerState==Player.STATE_IDLE
  // Explicit tap during a stuck buffer should rebuild the actual selected
  // source, even if the room continues to be marked "playing".
  val cannotAdvance=broken || playerState==Player.STATE_BUFFERING
  if(roomState=="playing" && cannotAdvance)return Action.RELOAD_LOCAL_PLAYER
  if(roomState=="paused" && broken)return Action.RELOAD_AND_PLAY_ROOM
  if(roomState=="playing" && stalled)return Action.WAKE_PLAYER
  return Action.TOGGLE_ROOM
 }
}
