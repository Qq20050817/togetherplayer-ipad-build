package dev.together.poc

/**
 * Detects a real video-frame freeze only during active playback.
 * Buffering, explicit pause and source recreation reset qualification.
 * This does not infer pixel quality or HDR output from an advancing clock.
 */
internal class HdrFrameProgressWatchdog(private val timeoutMs:Long=10_000L) {
 private var lastFrames:Long?=null
 private var lastAdvanceMs=0L

 fun isFrozen(nowMs:Long,displayedFrames:Long?,activelyPlaying:Boolean):Boolean {
  if(!activelyPlaying || displayedFrames==null || displayedFrames<0L){
   lastFrames=null;lastAdvanceMs=nowMs
   return false
  }
  if(lastFrames!=displayedFrames || nowMs<lastAdvanceMs){
   lastFrames=displayedFrames;lastAdvanceMs=nowMs
   return false
  }
  return nowMs-lastAdvanceMs>=timeoutMs
 }
}
