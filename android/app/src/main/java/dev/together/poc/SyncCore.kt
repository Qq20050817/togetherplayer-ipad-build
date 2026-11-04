package dev.together.poc

import android.os.SystemClock
import org.json.JSONObject
import kotlin.math.abs

interface PlayerAdapter {
 fun play(); fun pause(); fun seekTo(positionMs: Long)
 fun getPosition(): Long; fun getDuration(): Long
 fun isAdvancing():Boolean = true
 fun getBufferedAhead():Long = Long.MAX_VALUE
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
 private var explicitSeekVersion:Long?=null
 var isSyncWaiting=false;private set
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
  room=null; explicitSeekVersion=null;clock.reset();resetCorrection();lastAutoSeekAt=null;wasUnready=false;settleUntil=0.0
 }
 // Share this gate with the controller before applying media/UI side effects.
 fun accepts(next: JSONObject): Boolean =
  room?.optString("roomId") != next.optString("roomId") || next.getLong("version") >= version
 fun receive(next: JSONObject) {
  if (accepts(next)) {
   val previous=room
   if(previous?.optString("roomId") != next.optString("roomId") || next.getLong("version") != version) {resetCorrection();lastAutoSeekAt=null}
   if (previous?.optString("roomId") == next.optString("roomId") && next.optString("state") == "playing") {
    if (previous.optString("state") == "paused") settleUntil=clock.localNow()+2000
    else if (previous.optDouble("playbackRate",1.0) != next.optDouble("playbackRate",1.0)) settleUntil=clock.localNow()+2500
   }
   if(previous?.optString("roomId") != next.optString("roomId") || previous?.optString("mediaUrl") != next.optString("mediaUrl")) {
    explicitSeekVersion=next.getLong("version")
   } else if(next.getLong("version")>version) {
    val before=next.optJSONObject("before")
    val at=next.optDouble("updatedAt")
    val prior=if(before!=null && before.has("position")) before.optDouble("position") +
     (if(before.optString("state")=="playing") (at-before.optDouble("updatedAt")).coerceAtLeast(0.0)*before.optDouble("playbackRate",1.0) else 0.0) else Double.NaN
    explicitSeekVersion=if(prior.isFinite() && abs(next.optDouble("position")-prior)>150)next.getLong("version")else null
   }
   room=next
  }
 }
 private fun resetCorrection() {correctionSpeed=1f;excessiveDriftSince=null;isSyncWaiting=false}
 private fun speed(error: Double): Float {
  if(correctionSpeed>1 && error>1000)return correctionSpeed
  correctionSpeed=if(error>3000) {if(error>15000)1.25f else 1.10f} else if(error < -3000) .95f else 1f
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
  val r=room
  val timeline=if(r!=null && clock.serverNow()<r.optDouble("executeAt")) r.optJSONObject("before") else r
  val baseRate=if(timeline?.optDouble("playbackRate")==2.0) 2f else 1f
  if(explicitSeekVersion!=null){
   if(clock.serverNow()<(room?.optDouble("executeAt") ?: 0.0)){if(state=="playing")player.play()else player.pause();return error}
   if(state=="paused"){player.pause();player.setPlaybackSpeed(1f)}
   if(!player.isReady() && !player.isBuffering())return null
   explicitSeekVersion=null;resetCorrection();lastAutoSeekAt=now
   if(abs(error)>150)player.seekTo(position.toLong())
   player.setPlaybackSpeed(baseRate)
   if(state=="paused")player.pause()else player.play()
   return error
  }
  if(!player.isReady() || player.isBuffering()){wasUnready=true;isSyncWaiting=false}
  else if(wasUnready){wasUnready=false;settleUntil=now+2000}
  if (state=="paused") { resetCorrection();player.pause(); player.setPlaybackSpeed(1f); if (!player.isReady()) return null; if(abs(error)>3000 && lastAutoSeekAt==null) {lastAutoSeekAt=now;player.seekTo(position.toLong())}; return error }
  if (!player.isReady() || player.isBuffering()) {
   // Preserve ExoPlayer playWhenReady during 2x rebuffering and poll resume.
   if (player.isBuffering()) player.play()
   excessiveDriftSince=null;return null
  }
  // Pause only this device; never send a room PAUSE for drift correction.
  // Check a latched wait before isAdvancing: a deliberately paused decoder
  // cannot advance until the canonical timeline catches up.
  if(isSyncWaiting && error >= -1000) isSyncWaiting=false
  if(isSyncWaiting || (now>=settleUntil && player.isAdvancing() && error < -10000)) {
   isSyncWaiting=true;correctionSpeed=1f;excessiveDriftSince=null
   player.pause();player.setPlaybackSpeed(baseRate);return error
  }
  if(now<settleUntil){resetCorrection();player.setPlaybackSpeed(baseRate);player.play();return error}
  if(!player.isAdvancing() || (error>3000 && player.getBufferedAhead()<3000)){
   resetCorrection();player.setPlaybackSpeed(baseRate);player.play();return error
  }
  player.setPlaybackSpeed((baseRate*speed(error)).coerceAtMost(2.5f))
  player.play(); return error
 }
}
