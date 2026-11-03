package dev.together.poc
import android.net.Uri
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.media3.common.Player
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
@RunWith(AndroidJUnit4::class)
class LocalFirstHttpTest {
 private fun field(a:MainActivity,n:String)=a.javaClass.getDeclaredField(n).apply{isAccessible=true}
 private fun playback(a:MainActivity)=field(a,"playback").get(a) as CompatiblePlayback
 private fun welcome(a:MainActivity,room:JSONObject){a.javaClass.getDeclaredMethod("receive",JSONObject::class.java,Double::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,JSONObject().put("type","WELCOME").put("room",room),0.0)}
 @Test fun matchedLocalSurvivesReconnectAndBlocksForcedHttpReloadWithoutLosingSubtitle(){
  val i=InstrumentationRegistry.getInstrumentation();val bytes=i.context.assets.open("local-test.mp4").use{it.readBytes()}
  val file=java.io.File(i.targetContext.cacheDir,"local-first-fixture.mp4");file.writeBytes(bytes)
  try{FixtureHttpServer(bytes).use{remote->ActivityScenario.launch(MainActivity::class.java).use{scenario->
   val room=JSONObject().put("roomId","local-first").put("hostId","peer").put("mediaUrl",remote.url).put("title","Fixture").put("duration",8000).put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1)
   scenario.onActivity{a->welcome(a,room);field(a,"subtitleName").set(a,"fixture.srt");a.javaClass.getDeclaredMethod("useLocalMovie",Uri::class.java,Int::class.javaPrimitiveType,Boolean::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,Uri.fromFile(file),0,false)}
   var ready=false
   repeat(100){if(!ready){scenario.onActivity{a->ready=(field(a,"localFileUri").get(a) as String).isNotBlank() && playback(a).playbackState==Player.STATE_READY};SystemClock.sleep(100)}}
   assertTrue("matching HTTP/local bytes must bind and decode",ready)
   val requests=remote.server.requestCount
   scenario.onActivity{a->
    val p=playback(a);assertEquals(Uri.fromFile(file).toString(),p.currentMediaItem!!.localConfiguration!!.uri.toString())
    assertEquals("fixture.srt",field(a,"subtitleName").get(a))
    repeat(20){welcome(a,room)}
    a.javaClass.getDeclaredMethod("loadMedia",String::class.java,Double::class.javaPrimitiveType,Boolean::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,remote.url,1000.0,true)
    assertEquals(Uri.fromFile(file).toString(),p.currentMediaItem!!.localConfiguration!!.uri.toString())
   }
   SystemClock.sleep(700)
   assertEquals("local source must not reopen HTTP data or preload",requests,remote.server.requestCount)
   scenario.onActivity{a->a.javaClass.getDeclaredMethod("clearLocalMovie").apply{isAccessible=true}.invoke(a);assertEquals(remote.url,playback(a).currentMediaItem!!.localConfiguration!!.uri.toString());assertEquals("fixture.srt",field(a,"subtitleName").get(a))}
  }}}finally{file.delete()}
 }
 @Test fun duplicateTransientRetryPreservesRealPositionAndSubtitleWhileDisconnected(){
  val i=InstrumentationRegistry.getInstrumentation();val bytes=i.context.assets.open("local-test.mp4").use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->ActivityScenario.launch(MainActivity::class.java).use{scenario->
   val room=JSONObject().put("roomId","http-recovery").put("hostId","peer").put("mediaUrl",remote.url).put("title","Fixture").put("duration",8000).put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1)
   scenario.onActivity{a->welcome(a,room);field(a,"connected").set(a,false)}
   var ready=false
   repeat(80){if(!ready){scenario.onActivity{a->ready=playback(a).playbackState==Player.STATE_READY};SystemClock.sleep(100)}}
   assertTrue(ready)
   val count=remote.server.requestCount
   scenario.onActivity{a->
    val p=playback(a);p.seekTo(1500);field(a,"subtitleName").set(a,"preserved.srt")
    a.javaClass.getDeclaredMethod("markSourceFault").apply{isAccessible=true}.invoke(a)
    assertEquals(true,field(a,"sourceFault").get(a))
    val clock=field(a,"clock").get(a) as ClockSync;val now=clock.localNow();clock.add(now,now,now,now)
    val retry=a.javaClass.getDeclaredMethod("scheduleHttpErrorRecovery",Int::class.javaPrimitiveType,Int::class.javaObjectType,Boolean::class.javaPrimitiveType).apply{isAccessible=true}
    assertEquals(true,retry.invoke(a,androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,503,true))
    assertEquals(true,retry.invoke(a,androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,503,true))
    assertEquals(1,field(a,"playerRebuildCount").get(a))
    assertEquals("same-source recovery must retain fault until READY",true,field(a,"sourceFault").get(a))
   }
   var recovered=false
   repeat(80){if(!recovered){scenario.onActivity{a->recovered=remote.server.requestCount>count && playback(a).playbackState==Player.STATE_READY && playback(a).currentPosition>=1000};SystemClock.sleep(100)}}
   assertTrue("retry must preserve the real local playhead rather than paused room position zero",recovered)
   scenario.onActivity{a->assertEquals("READY must clear source fault",false,field(a,"sourceFault").get(a));assertEquals("preserved.srt",field(a,"subtitleName").get(a));assertFalse(playback(a).playWhenReady);assertEquals(remote.url,playback(a).currentMediaItem!!.localConfiguration!!.uri.toString())}
  }}
 }
 @Test fun invalidGrantDoesNotFallBackUntilUserExplicitlyClearsBinding(){
  val i=InstrumentationRegistry.getInstrumentation();val bytes=i.context.assets.open("local-test.mp4").use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->ActivityScenario.launch(MainActivity::class.java).use{scenario->
   val room=JSONObject().put("roomId","grant-reselect").put("hostId","peer").put("mediaUrl",remote.url).put("title","Fixture").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1)
   scenario.onActivity{a->welcome(a,room);field(a,"connected").set(a,false);playback(a).stop();field(a,"savedLocalPermissionMissing").set(a,true);field(a,"localSourceRoomID").set(a,"grant-reselect");field(a,"localSourceRoom").set(a,remote.url)}
   SystemClock.sleep(400);val count=remote.server.requestCount
   scenario.onActivity{a->a.javaClass.getDeclaredMethod("loadMedia",String::class.java,Double::class.javaPrimitiveType,Boolean::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,remote.url,0.0,true)}
   SystemClock.sleep(400);assertEquals(count,remote.server.requestCount)
   scenario.onActivity{a->assertTrue((field(a,"requestStatus").get(a) as android.widget.TextView).text.toString().contains("重新选择"));a.javaClass.getDeclaredMethod("clearLocalMovie").apply{isAccessible=true}.invoke(a);assertEquals(remote.url,playback(a).currentMediaItem!!.localConfiguration!!.uri.toString())}
  }}
 }

}
