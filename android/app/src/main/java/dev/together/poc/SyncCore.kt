package dev.together.poc

import android.os.SystemClock
import org.json.JSONObject
import kotlin.math.abs

interface PlayerAdapter {
 fun play(); fun pause(); fun seekTo(positionMs: Long)
 fun getPosition(): Long; fun getDuration(): Long
 fun isBuffering(): Boolean; fun isReady(): Boolean; fun setPlaybackSpeed(speed: Float)
}
interface MediaSourceAdapter { fun resolve(url: String): String }
class HTTPSource : MediaSourceAdapter {
 override fun resolve(url: String): String {
  require(url.startsWith("https://") || url.startsWith("http://"))
  return url
 }
}
class ClockSync(private val monotonicNow: () -> Double = { SystemClock.elapsedRealtimeNanos() / 1e6 }) {
 data class Sample(val offset: Double, val rtt: Double)
 private val samples = ArrayDeque<Sample>()
 var offset = 0.0; private set
 var rtt = 0.0; private set
 val ready get() = samples.isNotEmpty()
 fun localNow() = monotonicNow()
 fun serverNow() = localNow() + offset
 fun add(t1: Double, t2: Double, t3: Double, t4: Double) {
  val roundTrip = (t4-t1)-(t3-t2)
  if (roundTrip < 0 || roundTrip > 5000) return
  samples.addLast(Sample(((t2-t1)+(t3-t4))/2, roundTrip))
  while (samples.size > 8) samples.removeFirst()
  val best = samples.minBy { it.rtt }; offset=best.offset; rtt=roundTrip
 }
 fun reset() { samples.clear() }
}
class SyncEngine(private val player: PlayerAdapter, val clock: ClockSync) {
 var room: JSONObject? = null; private set
 private var correctionSpeed=1f
 private var excessiveDriftSince: Double?=null
 private var driftAtWindowStart=0.0
 private var lastAutoSeekAt: Double?=null
 private var wasUnready=false;private var settleUntil=0.0
 var timelineOffset=0.0
  set(value){if(field!=value){resetCorrection();lastAutoSeekAt=null};field=value}
 var resyncCount=0;private set
 val version get() = room?.optLong("version") ?: 0L
 fun resetSession() {
  player.pause(); player.setPlaybackSpeed(1f)
  room=null; clock.reset();resetCorrection();lastAutoSeekAt=null;wasUnready=false;settleUntil=0.0
 }
 fun receive(next: JSONObject) {
  if (room?.optString("roomId") != next.optString("roomId") || next.getLong("version") >= version) {
   if(room?.optString("roomId") != next.optString("roomId") || next.getLong("version") != version) {resetCorrection();lastAutoSeekAt=null}
   room=next
  }
 }
 private fun resetCorrection() {correctionSpeed=1f;excessiveDriftSince=null}
 private fun speed(error: Double): Float {
  val magnitude=abs(error)
  val sameDirection=(error>0 && correctionSpeed>1) || (error<0 && correctionSpeed<1)
  val fast=magnitude>=500 || (sameDirection && abs(correctionSpeed-1)>0.03 && magnitude>250)
  val gentle=magnitude>=200 || (sameDirection && abs(correctionSpeed-1)>0.001 && magnitude>100)
  correctionSpeed=if(fast) {if(error>0) 1.05f else .95f} else if(gentle) {if(error>0) 1.02f else .98f} else 1f
  return correctionSpeed
 }
 fun target(): Pair<Double, String>? {
  if (!clock.ready) return null
  val r=room ?: return null; val now=clock.serverNow()
  val t=if (now < r.getDouble("executeAt")) r.getJSONObject("before") else r
  val state=t.getString("state")
  val p=timelineOffset + t.getDouble("position") + if(state=="playing") (now-t.getDouble("updatedAt")).coerceAtLeast(0.0)*t.getDouble("playbackRate") else 0.0
  val duration=player.getDuration()
  if(duration>0 && p>=duration) return duration.toDouble() to "paused"
  return p.coerceAtLeast(0.0) to state
 }
 fun tick(): Double? {
  val (position,state) = target() ?: return null
  val error=position-player.getPosition()
  val now=clock.localNow()
  if(!player.isReady() || player.isBuffering())wasUnready=true
  else if(wasUnready){wasUnready=false;settleUntil=now+2000}
  if (state=="paused") { resetCorrection();player.pause(); player.setPlaybackSpeed(1f); if (!player.isReady()) return null; if(abs(error)>200) player.seekTo(position.toLong()); return error }
  if (!player.isReady() || player.isBuffering()) {excessiveDriftSince=null;return null}
  if(now<settleUntil){resetCorrection();player.setPlaybackSpeed(1f);player.play();return error}
  if(abs(error)>=500) {if(excessiveDriftSince==null) {excessiveDriftSince=now;driftAtWindowStart=abs(error)}} else excessiveDriftSince=null
  var overdue=excessiveDriftSince?.let {now-it>=10000} ?: false
  if(overdue && driftAtWindowStart-abs(error)>=100) {excessiveDriftSince=now;driftAtWindowStart=abs(error);overdue=false}
  val canSeek=lastAutoSeekAt?.let {now-it>=3000} ?: true
  if((abs(error)>1500 || overdue) && canSeek) {
   player.seekTo(position.toLong());player.setPlaybackSpeed(1f);resetCorrection();lastAutoSeekAt=now;resyncCount++
  } else player.setPlaybackSpeed(speed(error))
  player.play(); return error
 }
}
