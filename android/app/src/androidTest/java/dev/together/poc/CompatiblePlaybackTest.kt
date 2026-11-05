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

 @Test fun independentOutputKeepsMain10ColorsAcrossLongPlaybackAndReparent() = independentSoak("hevc-main10-soak-test.mp4",false)
 @Test fun main10MovieRateHttpKeepsColorsAudioAndPositionDuringCatchup() = independentSoak("hevc-main10-24fps-av-test.mkv",true)
 private fun independentSoak(asset:String,movieRate:Boolean){
  val i=InstrumentationRegistry.getInstrumentation()
  val bytes=i.context.assets.open(asset).use{it.readBytes()}
  FixtureHttpServer(bytes).use{remote->val uri=remote.url;ActivityScenario.launch(MainActivity::class.java).use{scenario->
   fun field(a:MainActivity,name:String)=a.javaClass.getDeclaredField(name).apply{isAccessible=true}
   fun player(a:MainActivity)=field(a,"playback").get(a) as CompatiblePlayback
   fun videoOutput(view:android.view.View):android.view.TextureView? {
    if(view is android.view.TextureView && view.isShown)return view
    if(view is android.view.ViewGroup)for(n in 0 until view.childCount){videoOutput(view.getChildAt(n))?.let{return it}}
    return null
   }
   var originalSurface:android.graphics.SurfaceTexture?=null
   fun assertColors(){
    val area=android.graphics.Rect();var position=0L;var outputDetails=""
    scenario.onActivity{a->
     val view=field(a,"independentVideoView").get(a) as android.view.View
     val output=videoOutput(view);assertNotNull("Compatibility output must use TextureView",output)
     assertTrue(output!!.getGlobalVisibleRect(area));position=player(a).currentPosition
     if(movieRate){val surface=output.surfaceTexture;assertNotNull(surface);if(originalSurface==null)originalSurface=surface else assertSame("Fullscreen must preserve the native video producer without disabling its track",originalSurface,surface)}
     val core=player(a).javaClass.getDeclaredField("vlc").apply{isAccessible=true}.get(player(a)) as org.videolan.libvlc.MediaPlayer
     outputDetails="videoTrack=${core.videoTrack},attached=${core.vlcVout.areViewsAttached()},playing=${core.isPlaying}"
    }
    if(movieRate){
     // TextureView spans the fullscreen parent; inspect the centered 3840:1600
     // picture, not the letterbox outside it.
     val contentHeight=area.width()*1600/3840
     if(contentHeight<area.height()){val top=area.top+(area.height()-contentHeight)/2;area.set(area.left,top,area.right,top+contentHeight)}
     else {val width=area.height()*3840/1600;val left=area.left+(area.width()-width)/2;area.set(left,area.top,left+width,area.bottom)}
    }
    // Read the actual composed screen off the main thread, including video.
    val bitmap=i.uiAutomation.takeScreenshot() ?: throw AssertionError("No composed screenshot")
    try {
     fun high(c:Int,mask:Int)=((c shr mask) and 255)>140
     fun low(c:Int,mask:Int)=((c shr mask) and 255)<110
     fun matches(n:Int,c:Int):Boolean {
      if(movieRate){
       val r=(c shr 16) and 255;val g=(c shr 8) and 255;val b=c and 255
       // HDR tone curves change brightness; chroma must still remain distinct.
       return when(n){0->r>g+50&&r>b+50;1->g>r+50&&g>b+50;2->r>b+50&&g>b+50;3->b>r+50&&b>g+50;4->r>g+50&&b>g+50;else->g>r+50&&b>r+50}
      }
      return when(n){
      0->high(c,16)&&low(c,8)&&low(c,0)
      1->high(c,8)&&low(c,16)&&low(c,0)
      2->high(c,16)&&high(c,8)&&low(c,0)
      3->high(c,0)&&low(c,16)&&low(c,8)
      4->high(c,16)&&high(c,0)&&low(c,8)
      else->high(c,8)&&high(c,0)&&low(c,16)
      }
     }
     for(n in 0 until 6){
      var matching=0
      for(x in 6..14 step 2)for(y in (if(movieRate)12..20 else 28..36) step 2){
       val c=bitmap.getPixel(area.left+(n*20+x)*area.width()/120,area.top+y*area.height()/64)
       if(matches(n,c))matching++
      }
      if(matching<15){
       val dir=java.io.File("/sdcard/Pictures/TogetherUITests").apply{mkdirs()}
       java.io.File(dir,"main10-color-failure.png").outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}
      }
      assertTrue("Main10 stripe $n must retain chroma: matches=$matching, position=$position, area=$area, $outputDetails",matching>=15)
     }
    } finally {bitmap.recycle()}
   }
   scenario.onActivity{a->val p=player(a);p.setMediaItem(MediaItem.fromUri(uri),0);assertTrue(p.activateCompatibility(uri,0,allowHttp=true))}
   var ready=false;val preparedDeadline=SystemClock.elapsedRealtime()+45000
   while(!ready && SystemClock.elapsedRealtime()<preparedDeadline){scenario.onActivity{a->assertNull(player(a).playerError);ready=player(a).playbackState==Player.STATE_READY};SystemClock.sleep(100)}
   assertTrue("Long Main10 fixture must prepare",ready)
   var syncNow=0.0;val syncClock=ClockSync{syncNow};syncClock.add(0.0,0.0,0.0,0.0)
   var sync:SyncEngine?=null;var syncSeeks=0
   scenario.onActivity{a->
    val p=player(a);p.volume=.7f
    if(movieRate){
     sync=SyncEngine(Media3Adapter(p){syncSeeks++;p.seekTo(it)},syncClock)
     sync!!.receive(org.json.JSONObject().put("roomId","movie-rate-catchup").put("mediaUrl",uri).put("version",1).put("executeAt",0).put("updatedAt",0).put("state","playing").put("position",p.currentPosition).put("playbackRate",1))
     sync!!.tick();sync!!.timelineOffset=10000.0
    }else p.play()
   }
   val start=SystemClock.elapsedRealtime();var reparented=false;var restored=false;var samples=0;var accelerated=false;var normalized=false;var nextSample=2500L
   while(SystemClock.elapsedRealtime()-start<38000){
    SystemClock.sleep(if(movieRate)100 else 2500)
    var sample=false
    scenario.onActivity{a->
     val p=player(a);assertNull(p.playerError);assertTrue("Long Main10 decode must continue",p.displayedFrames()>0)
     val elapsed=SystemClock.elapsedRealtime()-start
     if(movieRate){
      syncNow=elapsed.toDouble();if(elapsed>12000)sync!!.timelineOffset=0.0
      sync!!.tick()
      val core=p.javaClass.getDeclaredField("vlc").apply{isAccessible=true}.get(p) as org.videolan.libvlc.MediaPlayer
      if(core.rate>1f)accelerated=true
      if(accelerated && elapsed>12000 && core.rate==1f)normalized=true
      assertEquals("Advancing lag must never become an automatic seek",0,syncSeeks)
     }
     if(movieRate && elapsed>=nextSample && elapsed>10000){
      val source=p.javaClass.getDeclaredField("source").apply{isAccessible=true}.get(p) as org.videolan.libvlc.Media
      val core=p.javaClass.getDeclaredField("vlc").apply{isAccessible=true}.get(p) as org.videolan.libvlc.MediaPlayer
      val stats=source.stats ?: throw AssertionError("Missing native input statistics")
      assertTrue("Movie audio must be decoded",stats.decodedAudio>0)
      assertTrue("Movie audio must reach the output",stats.playedAbuffers>0)
      assertTrue("Movie audio track must remain selected",core.audioTrack>=0)
      assertEquals("Volume must survive preparation and output rebind",70,core.volume)
     }
     if(SystemClock.elapsedRealtime()-start>12000 && !reparented){a.javaClass.getDeclaredMethod("showFullscreen").apply{isAccessible=true}.invoke(a);reparented=true}
     else if(SystemClock.elapsedRealtime()-start>22000 && !restored){(field(a,"fullscreenDialog").get(a) as android.app.Dialog).dismiss();restored=true}
     else if(!movieRate || elapsed>=nextSample){sample=true;samples++;nextSample=elapsed+2500}
    }
    if(sample)assertColors()
   }
   scenario.onActivity{a->val p=player(a);assertTrue("Native clock must advance through at least30s",p.currentPosition>=30000);p.pause();assertFalse(p.playWhenReady)}
   assertColors()
   assertTrue("Check color planes repeatedly, not only first-frame count",samples>=8);assertTrue(reparented&&restored)
   if(movieRate){
    assertTrue("Sustained real HTTP lag must change the actual independent decoder rate",accelerated)
    assertTrue("Recovered drift must restore the actual decoder rate",normalized)
    scenario.onActivity{a->player(a).seekTo(5000)}
    val until=SystemClock.elapsedRealtime()+10000;var confirmed=false
    while(!confirmed && SystemClock.elapsedRealtime()<until){scenario.onActivity{a->assertNull(player(a).playerError);confirmed=player(a).currentPosition in 4500..5500};SystemClock.sleep(100)}
    assertTrue("Paused HTTP Main10 seek must be confirmed by the native clock",confirmed)
    assertColors()
   }
  }}
 }

}
