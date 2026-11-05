package dev.together.poc

import android.os.SystemClock
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.Request
import okhttp3.WebSocket
import okio.ByteString
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CompatibleHttpRecoveryTest {
 private class Socket:WebSocket {
  override fun request()=Request.Builder().url("https://example.invalid/ws").build()
  override fun queueSize()=0L
  override fun send(text:String)=true
  override fun send(bytes:ByteString)=true
  override fun close(code:Int,reason:String?)=true
  override fun cancel(){}
 }
 private fun field(a:MainActivity,n:String)=a.javaClass.getDeclaredField(n).apply{isAccessible=true}
 private fun player(a:MainActivity)=field(a,"playback").get(a) as CompatiblePlayback
 private fun input(a:MainActivity)=player(a).javaClass.getDeclaredField("source").apply{isAccessible=true}.get(player(a))
 private fun fail(a:MainActivity)=player(a).javaClass.getDeclaredMethod("fail",String::class.java).apply{isAccessible=true}.invoke(player(a),"Synthetic input interruption")
 private fun awaitReady(s:ActivityScenario<MainActivity>,old:Any?=null){
  var ready=false;val end=SystemClock.elapsedRealtime()+45000
  while(!ready && SystemClock.elapsedRealtime()<end){s.onActivity{a->ready=player(a).compatibleActive && player(a).playerError==null && player(a).playbackState==Player.STATE_READY && input(a)!==old};SystemClock.sleep(100)}
  assertTrue("Independent HTTP input must reopen and display a real frame",ready)
 }
 private fun start(a:MainActivity,uri:String){
  val p=player(a);val engine=field(a,"engine").get(a) as SyncEngine
  val clock=field(a,"clock").get(a) as ClockSync;val now=clock.localNow();clock.add(now,now,now,now)
  engine.receive(JSONObject().put("roomId","independent-recovery").put("hostId","peer").put("mediaUrl",uri).put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",2000).put("playbackRate",1))
  field(a,"ws").set(a,Socket());field(a,"connected").set(a,true)
  (field(a,"httpHealth").get(a) as HttpPlaybackHealth).reset(uri)
  field(a,"subtitleName").set(a,"kept.srt")
  p.setMediaItem(MediaItem.fromUri(uri),2000);assertTrue(p.activateCompatibility(uri,2000,allowHttp=true));p.volume=.7f
 }
 @Test fun failedIndependentHttpReopensAtRealPositionKeepsPauseTracksAndBoundedBudget(){
  val i=InstrumentationRegistry.getInstrumentation();i.targetContext.getSharedPreferences("MainActivity",0).edit().clear().commit()
  val bytes=i.context.assets.open("hevc-main10-soak-test.mp4").use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->val uri=remote.url;ActivityScenario.launch(MainActivity::class.java).use{s->
   s.onActivity{start(it,uri)};awaitReady(s)
   var old:Any?=null;var audio=-1
   s.onActivity{a->old=input(a);audio=player(a).selectedCompatibleTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO);assertTrue(audio>=0);player(a).selectCompatibleTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO,audio);fail(a);fail(a);assertEquals(1,(field(a,"httpRetryBudget").get(a) as HttpRetryBudget).attempts)}
   awaitReady(s,old)
   s.onActivity{a->val p=player(a);assertEquals(uri,p.currentMediaItem!!.localConfiguration!!.uri.toString());assertTrue("Resume uses real playhead",p.currentPosition in 1500..2500);assertFalse(p.playWhenReady);assertFalse(p.isPlaying);assertEquals(audio,p.selectedCompatibleTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO));assertEquals(.7f,p.volume,.01f);assertEquals("kept.srt",field(a,"subtitleName").get(a));assertEquals(false,field(a,"sourceFault").get(a));old=input(a);fail(a)}
   awaitReady(s,old)
   s.onActivity{a->assertEquals(2,(field(a,"httpRetryBudget").get(a) as HttpRetryBudget).attempts);assertFalse(player(a).playWhenReady);fail(a);assertFalse(field(a,"networkRecoveryScheduled").get(a) as Boolean)}
   val requests=remote.server.requestCount;SystemClock.sleep(4500)
   assertEquals("Consecutive failures must not create an infinite read loop",requests,remote.server.requestCount)
   s.onActivity{a->assertNotNull(player(a).playerError);assertFalse(player(a).isPlaying);player(a).clearMediaItems()}
  }}
 }
 @Test fun sourceSwitchCancelsQueuedIndependentRecovery(){
  val i=InstrumentationRegistry.getInstrumentation();i.targetContext.getSharedPreferences("MainActivity",0).edit().clear().commit()
  val bytes=i.context.assets.open("hevc-main10-soak-test.mp4").use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->val uri=remote.url;ActivityScenario.launch(MainActivity::class.java).use{s->
   s.onActivity{start(it,uri)};awaitReady(s)
   val replacement="https://example.invalid/replacement.mp4"
   s.onActivity{a->fail(a);player(a).setMediaItem(MediaItem.fromUri(replacement),0);field(a,"connected").set(a,false)}
   val requests=remote.server.requestCount;SystemClock.sleep(2500)
   assertEquals("Old HTTP input must not reopen after the device changes sources",requests,remote.server.requestCount)
   s.onActivity{a->assertEquals(replacement,player(a).currentMediaItem!!.localConfiguration!!.uri.toString());assertFalse(player(a).compatibleActive);player(a).clearMediaItems()}
  }}
 }
}
