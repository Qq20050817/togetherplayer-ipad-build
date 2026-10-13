package dev.together.poc

/**
 * Keeps transport taps responsive while asynchronous decoders and the room
 * acknowledgement are still catching up. All positions are room milliseconds.
 */
class SeekTapAccumulator {
 private var lastTarget:Double?=null
 private var lastAt=Double.NEGATIVE_INFINITY

 fun next(current:Double,delta:Double,now:Double,duration:Double,offset:Double):Double {
  if(!delta.isFinite())return current.coerceAtLeast(0.0)
  val previous=lastTarget
  val base=if(previous!=null && now.isFinite() && now-lastAt in 0.0..1300.0)previous
           else if(current.isFinite())current else 0.0
  val maximum=if(duration.isFinite() && duration>0) (duration-offset).coerceAtLeast(0.0) else Double.MAX_VALUE
  val target=(base+delta).coerceIn(0.0,maximum)
  lastTarget=target;lastAt=now
  return target
 }
 fun reset(){lastTarget=null;lastAt=Double.NEGATIVE_INFINITY}
}
