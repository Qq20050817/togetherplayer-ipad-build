package dev.together.poc

import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.upstream.DefaultAllocator
import java.util.Locale

/**
 * In-memory diagnostics for the active HTTP media item.
 * Never stores or reports a URL, bearer token, signed query or movie path.
 * State is written by the main thread and read by ExoPlayer's playback thread.
 */
class HttpPlaybackHealth {
 @Volatile var isHttp=false
  private set
 @Volatile var speedMbps: Double?=null
  private set
 @Volatile var stalls=0
  private set
 @Volatile var lastStallElapsedMs=0L
  private set
 @Volatile var remainingMs=Long.MAX_VALUE
  private set
 private var seenReady=false
 private var lastState=Player.STATE_IDLE

 fun reset(source:String) {
  isHttp=source.startsWith("http://",true) || source.startsWith("https://",true)
  speedMbps=null;stalls=0;lastStallElapsedMs=0;remainingMs=Long.MAX_VALUE
  seenReady=false;lastState=Player.STATE_IDLE
 }

 fun onBandwidthEstimate(loadTimeMs:Int,bytes:Long,estimateBitsPerSecond:Long) {
  if(!isHttp || loadTimeMs<=0 || bytes<32*1024L)return
  val rate=if(estimateBitsPerSecond>0)estimateBitsPerSecond.toDouble()/1_000_000.0
   else bytes*8.0/loadTimeMs/1000.0
  if(rate.isFinite() && rate>0 && rate<100_000) speedMbps=rate
 }

 fun onPlaybackState(state:Int,playWhenReady:Boolean,elapsedMs:Long) {
  if(!isHttp){lastState=state;return}
  if(state==Player.STATE_READY)seenReady=true
  if(state==Player.STATE_BUFFERING && lastState!=Player.STATE_BUFFERING && seenReady && playWhenReady) {
   stalls=(stalls+1).coerceAtMost(99)
   lastStallElapsedMs=elapsedMs
  }
  lastState=state
 }

 fun setRemaining(durationMs:Long,positionMs:Long) {
  remainingMs=if(durationMs>0) (durationMs-positionMs).coerceAtLeast(0) else Long.MAX_VALUE
 }

 fun resumeReserveMs():Long = when {
  stalls>=3->20_000L
  stalls>=2->16_000L
  else->12_000L
 }

 fun display(bufferedMs:Long):String {
  if(!isHttp)return ""
  val rate=speedMbps?.let {String.format(Locale.US,"%.1f Mbps",it)} ?: "速度待测"
  val buffer=(bufferedMs.coerceAtLeast(0L)/1000L)
  return "HTTP $rate · 已缓冲 ${buffer}s · 卡顿 ${stalls}次"
 }
}

/**
 * Preserve existing local playback and initial click-to-play timing.
 * After repeated HTTP rebuffering, raise the recovery reserve for stability,
 * but never make a short remaining tail or slow network wait indefinitely.
 */
class AdaptiveHttpLoadControl(private val health:HttpPlaybackHealth):DefaultLoadControl(
 DefaultAllocator(true,65536),
 30_000,60_000,8_000,12_000,
 C.LENGTH_UNSET,true,0,false
) {
 override fun shouldStartPlayback(parameters:LoadControl.Parameters):Boolean {
  if(!health.isHttp || !parameters.rebuffering || health.stalls<2)
   return super.shouldStartPlayback(parameters)
  val targetMs=minOf(health.resumeReserveMs(),health.remainingMs)
  if(targetMs<=12_000L) return super.shouldStartPlayback(parameters)
  // LoadControl is called on ExoPlayer's playback thread, independent of UI.
  val elapsed=android.os.SystemClock.elapsedRealtime()-health.lastStallElapsedMs
  if(elapsed>=25_000L)return super.shouldStartPlayback(parameters)
  val bufferedMs=parameters.bufferedDurationUs.coerceAtLeast(0)/1000.0 /
   parameters.playbackSpeed.toDouble().coerceAtLeast(0.1)
  return bufferedMs>=targetMs
 }
}
