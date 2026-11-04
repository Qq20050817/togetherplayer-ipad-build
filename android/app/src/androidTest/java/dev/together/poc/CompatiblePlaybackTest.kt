package dev.together.poc
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import android.os.SystemClock
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
@RunWith(AndroidJUnit4::class)
class CompatiblePlaybackTest {
 @Test fun main10FallbackDisplaysFrameStaysPausedSeeksAndSwitchesBack() {
  val i=InstrumentationRegistry.getInstrumentation();val file=java.io.File(i.targetContext.cacheDir,"main10-playback.mp4")
  i.context.assets.open("hevc-main10-4k-test.mp4").use {s->file.outputStream().use {s.copyTo(it)}}
  try {ActivityScenario.launch(MainActivity::class.java).use {scenario->
   fun playback(a:MainActivity)=a.javaClass.getDeclaredField("playback").apply{isAccessible=true}.get(a) as CompatiblePlayback
   val uri=android.net.Uri.fromFile(file).toString()
   scenario.onActivity {a->val p=playback(a);p.setMediaItem(MediaItem.fromUri(uri),0);val format=androidx.media3.common.Format.Builder().setSampleMimeType("video/hevc").setCodecs("hvc1.2.4.H153.90").setWidth(3840).setHeight(2076).build();assertTrue(a.javaClass.getDeclaredMethod("tryRecoverVideoDecoder",androidx.media3.common.Format::class.java,String::class.java).apply{isAccessible=true}.invoke(a,format,"injected.failed.main10.decoder") as Boolean);p.volume=.7f}
   var ready=false
   val deadline=SystemClock.elapsedRealtime()+45000
   while(!ready && SystemClock.elapsedRealtime()<deadline){scenario.onActivity {a->val p=playback(a);assertNull(p.playerError);ready=p.playbackState==Player.STATE_READY};SystemClock.sleep(100)}
   assertTrue("Integrated fallback did not display a real frame",ready)
   scenario.onActivity {a->val p=playback(a);assertTrue(p.displayedFrames()>0);assertTrue(p.decodedFrames()>0);assertTrue(p.duration>0);assertFalse("Preparing must not autoplay a paused room",p.playWhenReady);assertFalse(p.isPlaying);assertEquals(.7f,p.volume,.01f);p.volume=0f;assertEquals(0f,p.volume,.001f);p.seekTo(1000);p.play();assertTrue(p.playWhenReady);p.pause();assertFalse(p.playWhenReady)
    val clock=ClockSync {0.0};clock.add(0.0,0.0,0.0,0.0);val engine=SyncEngine(Media3Adapter(p),clock)
    val room=org.json.JSONObject().put("roomId","main10-sync").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","playing").put("position",1000).put("playbackRate",1)
    engine.receive(room);engine.tick();assertTrue("Room PLAY must reach independent player",p.playWhenReady)
    engine.receive(org.json.JSONObject(room.toString()).put("version",2).put("state","paused"));engine.tick();assertFalse("Room PAUSE must stop independent player",p.playWhenReady)
   }
   SystemClock.sleep(400)
   scenario.onActivity {a->val p=playback(a);assertFalse(p.isPlaying);p.setMediaItem(MediaItem.fromUri("https://example.invalid/next.mp4"),0);assertFalse(p.compatibleActive);assertFalse(p.activateCompatibility("https://example.invalid/next.mp4",0));p.clearMediaItems()}
  }} finally {file.delete()}
 }
 @Test fun main10HttpRecoveryDisplaysFrameAtRealPositionAndPreservesSubtitleWithoutAutoplay(){
  val i=InstrumentationRegistry.getInstrumentation()
  val bytes=i.context.assets.open("hevc-main10-http-test.mp4").use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->val uri=remote.url;ActivityScenario.launch(MainActivity::class.java).use{scenario->
   fun field(a:MainActivity,name:String)=a.javaClass.getDeclaredField(name).apply{isAccessible=true}
   fun playback(a:MainActivity)=field(a,"playback").get(a) as CompatiblePlayback
   scenario.onActivity{a->
    val p=playback(a);p.setMediaItem(MediaItem.fromUri(uri),1500)
    field(a,"subtitleName").set(a,"kept.srt");field(a,"sourceFault").set(a,true)
    val recovery=field(a,"decoderRecovery").get(a) as VideoDecoderRecovery
    recovery.beginSource(uri)
    assertNotNull(recovery.recover("video/hevc","failed.one",listOf("next.one")))
    assertNotNull(recovery.recover("video/hevc","failed.two",listOf("next.two")))
    val format=androidx.media3.common.Format.Builder().setSampleMimeType("video/hevc").setCodecs("hvc1.2.4.H153.90").setWidth(3840).setHeight(2076).build()
    assertTrue(a.javaClass.getDeclaredMethod("tryRecoverVideoDecoder",androidx.media3.common.Format::class.java,String::class.java).apply{isAccessible=true}.invoke(a,format,"failed.final") as Boolean)
   }
   var ready=false;var details="";val deadline=SystemClock.elapsedRealtime()+45000
   while(!ready && SystemClock.elapsedRealtime()<deadline){scenario.onActivity{a->val p=playback(a);assertNull(p.playerError);ready=p.playbackState==Player.STATE_READY;val view=field(a,"independentVideoView").get(a) as android.view.View;details="state=${p.playbackState},decoded=${p.decodedFrames()},displayed=${p.displayedFrames()},position=${p.currentPosition},duration=${p.duration},requests=${remote.server.requestCount},shown=${view.isShown},size=${view.width}x${view.height}"};SystemClock.sleep(100)}
   assertTrue("HTTP HEVC Main10 fallback must display an actual video frame: $details",ready)
   scenario.onActivity{a->
    val p=playback(a);assertTrue(p.compatibleActive);assertTrue(p.displayedFrames()>0);assertTrue(p.currentPosition>=1000)
    assertFalse("preparing HTTP recovery must not autoplay",p.playWhenReady);assertFalse(p.isPlaying)
    assertEquals(uri,p.currentMediaItem!!.localConfiguration!!.uri.toString());assertEquals("kept.srt",field(a,"subtitleName").get(a))
    assertEquals("actual independent READY clears the source fault",false,field(a,"sourceFault").get(a))
    p.seekTo(2000);p.play();assertTrue(p.playWhenReady);p.pause();assertFalse(p.playWhenReady)
    p.setMediaItem(MediaItem.fromUri("https://example.invalid/next.mp4"),0);assertFalse(p.compatibleActive)
    assertFalse("ordinary HTTP must still require explicit fallback",p.activateCompatibility("https://example.invalid/next.mp4",0))
    p.clearMediaItems()
   }
  }}
 }

 @Test fun textureOutputKeepsMain10ColorsAcrossLongPlaybackAndReparent(){
  val i=InstrumentationRegistry.getInstrumentation()
  val bytes=i.context.assets.open("hevc-main10-soak-test.mp4").use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->val uri=remote.url;ActivityScenario.launch(MainActivity::class.java).use{scenario->
   fun field(a:MainActivity,name:String)=a.javaClass.getDeclaredField(name).apply{isAccessible=true}
   fun player(a:MainActivity)=field(a,"playback").get(a) as CompatiblePlayback
   fun texture(view:android.view.View):android.view.TextureView? {
    if(view is android.view.TextureView && view.isShown)return view
    if(view is android.view.ViewGroup)for(n in 0 until view.childCount){texture(view.getChildAt(n))?.let{return it}}
    return null
   }
   fun assertColors(a:MainActivity){
    val view=field(a,"independentVideoView").get(a) as android.view.View
    val output=texture(view);assertNotNull("Compatibility output must use the texture path",output)
    val bitmap=output!!.getBitmap(120,64);assertNotNull(bitmap)
    try {
     val colors=(0 until 6).map{n->bitmap!!.getPixel(n*20+10,12)}
     fun high(c:Int,mask:Int)=((c shr mask) and 255)>140
     fun low(c:Int,mask:Int)=((c shr mask) and 255)<110
     assertTrue("Main10 red stripe must retain chroma",high(colors[0],16)&&low(colors[0],8)&&low(colors[0],0))
     assertTrue("Main10 green stripe must retain chroma",high(colors[1],8)&&low(colors[1],16)&&low(colors[1],0))
     assertTrue("Main10 yellow stripe must retain chroma",high(colors[2],16)&&high(colors[2],8)&&low(colors[2],0))
     assertTrue("Main10 blue stripe must retain chroma",high(colors[3],0)&&low(colors[3],16)&&low(colors[3],8))
     assertTrue("Main10 magenta stripe must retain chroma",high(colors[4],16)&&high(colors[4],0)&&low(colors[4],8))
     assertTrue("Main10 cyan stripe must retain chroma",high(colors[5],8)&&high(colors[5],0)&&low(colors[5],16))
    } finally {bitmap?.recycle()}
   }
   scenario.onActivity{a->val p=player(a);p.setMediaItem(MediaItem.fromUri(uri),0);assertTrue(p.activateCompatibility(uri,0,allowHttp=true))}
   var ready=false;val preparedDeadline=SystemClock.elapsedRealtime()+45000
   while(!ready && SystemClock.elapsedRealtime()<preparedDeadline){scenario.onActivity{a->assertNull(player(a).playerError);ready=player(a).playbackState==Player.STATE_READY};SystemClock.sleep(100)}
   assertTrue("Long Main10 fixture must prepare",ready)
   scenario.onActivity{a->assertColors(a);player(a).play()}
   val start=SystemClock.elapsedRealtime();var reparented=false;var restored=false;var samples=0
   while(SystemClock.elapsedRealtime()-start<38000){
    SystemClock.sleep(2500)
    scenario.onActivity{a->
     val p=player(a);assertNull(p.playerError);assertTrue("Long Main10 decode must continue",p.displayedFrames()>0)
     if(SystemClock.elapsedRealtime()-start>12000 && !reparented){a.javaClass.getDeclaredMethod("showFullscreen").apply{isAccessible=true}.invoke(a);reparented=true}
     else if(SystemClock.elapsedRealtime()-start>22000 && !restored){(field(a,"fullscreenDialog").get(a) as android.app.Dialog).dismiss();restored=true}
     else {assertColors(a);samples++}
    }
   }
   scenario.onActivity{a->val p=player(a);assertTrue("Native clock must advance through at least30s",p.currentPosition>=30000);p.pause();assertFalse(p.playWhenReady);assertColors(a)}
   assertTrue("Check color planes repeatedly, not only first-frame count",samples>=8);assertTrue(reparented&&restored)
  }}
 }

}
