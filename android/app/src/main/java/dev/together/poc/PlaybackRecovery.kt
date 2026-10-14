package dev.together.poc

import kotlin.math.abs

// Room state can be "playing" even when the local decoder has stopped making
// progress. Recover without another document picker or losing room identity.
class PlaybackRecovery {
 enum class Action {NONE, WAKE, REBUILD}
 private var stallSince:Double?=null
 private var lastPosition:Long?=null
 private var stage=0
 val isStalled get()=stage>0
 fun reset(){stallSince=null;lastPosition=null;stage=0}
 fun observe(now:Double,position:Long,shouldPlay:Boolean):Action {
  if(!shouldPlay || !now.isFinite() || position<0){reset();return Action.NONE}
  val previous=lastPosition
  if(previous==null || abs(position-previous)>=150){stallSince=now;lastPosition=position;stage=0;return Action.NONE}
  val elapsed=now-(stallSince ?: now)
  if(elapsed>=14000 && stage==1){stage=2;return Action.REBUILD}
  if(elapsed>=5000 && stage==0){stage=1;return Action.WAKE}
  return Action.NONE
 }
}
