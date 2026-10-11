package dev.together.poc
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.UiDevice
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import android.graphics.Rect
import android.os.SystemClock
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
@RunWith(AndroidJUnit4::class)
class EmbeddedSubtitleTest {
 @Test fun compatibleFullscreenCanImportSubtitleThroughActualFiles() {
  val i=InstrumentationRegistry.getInstrumentation();val resolver=i.targetContext.contentResolver
  val name="TOGETHER-COMPATIBILITY-SUBTITLE.srt"
  val values=android.content.ContentValues().apply {
   put(android.provider.MediaStore.Downloads.DISPLAY_NAME,name)
   put(android.provider.MediaStore.Downloads.MIME_TYPE,"application/x-subrip")
   put(android.provider.MediaStore.Downloads.RELATIVE_PATH,"Download/")
  }
  val subtitle=resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,values)!!
  val movie=java.io.File(i.targetContext.cacheDir,"subtitle-import-test.mkv")
  try {
   resolver.openOutputStream(subtitle)!!.use {it.write("1\n00:00:00,000 --> 00:00:19,500\nImported subtitle visible\n".toByteArray())}
   i.context.assets.open("embedded-pgs.mkv").use {input->movie.outputStream().use {input.copyTo(it)}}
   ActivityScenario.launch(MainActivity::class.java).use {scenario->
    fun player(a:MainActivity)=a.javaClass.getDeclaredField("playback").apply{isAccessible=true}.get(a) as CompatiblePlayback
    scenario.onActivity {a->val p=player(a);val uri=android.net.Uri.fromFile(movie).toString();p.setMediaItem(MediaItem.fromUri(uri),0);assertTrue(p.activateCompatibility(uri,0))}
    var ready=false;val deadline=SystemClock.elapsedRealtime()+15000
    while(!ready && SystemClock.elapsedRealtime()<deadline){scenario.onActivity {ready=player(it).playbackState==Player.STATE_READY};SystemClock.sleep(100)}
    assertTrue(ready)
    scenario.onActivity {a->
     val p=player(a);p.selectCompatibleTrack(C.TRACK_TYPE_TEXT,p.compatibleTracks(C.TRACK_TYPE_TEXT).first().id);p.play()
     a.javaClass.getDeclaredMethod("showFullscreen").apply{isAccessible=true}.invoke(a)
     a.javaClass.getDeclaredMethod("importSubtitle").apply{isAccessible=true}.invoke(a)
    }
    val device=UiDevice.getInstance(i)
    assertTrue(device.wait(androidx.test.uiautomator.Until.hasObject(androidx.test.uiautomator.By.pkg("com.google.android.documentsui")),5000))
    var entry=device.wait(androidx.test.uiautomator.Until.findObject(androidx.test.uiautomator.By.text(name)),2000)
    if(entry==null){device.findObject(androidx.test.uiautomator.By.desc("Show roots"))?.click();device.wait(androidx.test.uiautomator.Until.findObject(androidx.test.uiautomator.By.text("Downloads")),3000)?.click();entry=device.wait(androidx.test.uiautomator.Until.findObject(androidx.test.uiautomator.By.text(name)),5000)}
    assertNotNull("Subtitle must be selectable in actual system Files",entry);entry!!.click()
    assertTrue(device.wait(androidx.test.uiautomator.Until.hasObject(androidx.test.uiautomator.By.pkg("dev.together.poc")),5000))
    var loaded=false
    repeat(50){if(!loaded){scenario.onActivity {a->loaded=a.javaClass.getDeclaredField("subtitleName").apply{isAccessible=true}.get(a)==name};SystemClock.sleep(100)}}
    assertTrue("Subtitle result must return without crashing",loaded)
    scenario.onActivity {a->val p=player(a);assertTrue(p.compatibleActive);assertEquals("File picker must not destroy the decoder input",Player.STATE_READY,p.playbackState);assertTrue(p.duration>0);p.play()}
    SystemClock.sleep(1000)
    scenario.onActivity {a->val captions=a.javaClass.getDeclaredField("captions").apply{isAccessible=true}.get(a) as android.widget.TextView;assertEquals("Imported subtitle visible",captions.text.toString());assertEquals(android.view.View.VISIBLE,captions.visibility);assertTrue(player(a).displayedFrames()>0);player(a).pause()}
   }
  } finally {resolver.delete(subtitle,null,null);movie.delete()}
 }

 @Test fun selectedEmbeddedSubtitleProducesVisiblePixels()=verifyVisibleSubtitle("embedded-subtitle.mkv")
 @Test fun selectedPGSSubtitleProducesVisiblePixels()=verifyVisibleSubtitle("embedded-pgs.mkv")
 private fun verifyVisibleSubtitle(asset:String) {
  val i=InstrumentationRegistry.getInstrumentation();val file=java.io.File(i.targetContext.cacheDir,asset)
  i.context.assets.open(asset).use {s->file.outputStream().use {s.copyTo(it)}}
  val device=UiDevice.getInstance(i)
  try {ActivityScenario.launch(MainActivity::class.java).use {scenario->
   fun player(a:MainActivity)=a.javaClass.getDeclaredField("playback").apply{isAccessible=true}.get(a) as CompatiblePlayback
   val uri=android.net.Uri.fromFile(file).toString();val area=Rect()
   scenario.onActivity {a->val p=player(a);p.setMediaItem(MediaItem.fromUri(uri),0);assertTrue(p.activateCompatibility(uri,0))}
   var ready=false;val deadline=SystemClock.elapsedRealtime()+15000
   while(!ready && SystemClock.elapsedRealtime()<deadline){scenario.onActivity {a->val p=player(a);assertNull(p.playerError);ready=p.playbackState==Player.STATE_READY};SystemClock.sleep(100)}
   assertTrue(ready)
   scenario.onActivity {a->val p=player(a);assertTrue(p.compatibleTracks(C.TRACK_TYPE_TEXT).isNotEmpty());p.selectCompatibleTrack(C.TRACK_TYPE_TEXT,-1);p.play();val box=a.javaClass.getDeclaredField("videoBox").apply{isAccessible=true}.get(a) as android.view.View;box.getGlobalVisibleRect(area)}
   SystemClock.sleep(700)
   fun brightPixels():Int {
    val bitmap=i.uiAutomation.takeScreenshot() ?: throw AssertionError("No real screenshot")
    var count=0
    for(y in (area.top+area.height()/2).coerceAtLeast(0) until area.bottom.coerceAtMost(bitmap.height))for(x in area.left.coerceAtLeast(0) until area.right.coerceAtMost(bitmap.width)) {val c=bitmap.getPixel(x,y);if(android.graphics.Color.red(c)>180 && android.graphics.Color.green(c)>180 && android.graphics.Color.blue(c)>180)count++}
    bitmap.recycle();return count
   }
   val closed=brightPixels()
   scenario.onActivity {a->val p=player(a);p.selectCompatibleTrack(C.TRACK_TYPE_TEXT,p.compatibleTracks(C.TRACK_TYPE_TEXT).first().id);p.seekTo(3000);p.play()}
   SystemClock.sleep(1200)
   val shown=brightPixels()
   java.io.File("/sdcard/Pictures/TogetherUITests").mkdirs();device.takeScreenshot(java.io.File("/sdcard/Pictures/TogetherUITests/$asset.png"))
   assertTrue("Selected embedded subtitle has no visible pixels: off=$closed on=$shown rect=$area",shown>closed+100)
   scenario.onActivity {a->
    assertTrue(player(a).selectedCompatibleTrack(C.TRACK_TYPE_TEXT)>=0)
    a.javaClass.getDeclaredMethod("showFullscreen").apply{isAccessible=true}.invoke(a)
   }
   SystemClock.sleep(1000)
   scenario.onActivity {a->val box=a.javaClass.getDeclaredField("videoBox").apply{isAccessible=true}.get(a) as android.view.View;box.getGlobalVisibleRect(area);player(a).seekTo(6000)}
   SystemClock.sleep(1200)
   // PGS can only rebuild an image when its next complete palette/object cue arrives.
   SystemClock.sleep(1400)
   val fullShown=brightPixels()
   device.takeScreenshot(java.io.File("/sdcard/Pictures/TogetherUITests/$asset-fullscreen.png"))
   scenario.onActivity {a->player(a).selectCompatibleTrack(C.TRACK_TYPE_TEXT,-1)}
   SystemClock.sleep(500)
   val fullClosed=brightPixels()
   assertTrue("Fullscreen/seek subtitle missing: off=$fullClosed on=$fullShown rect=$area",fullShown>fullClosed+100)
   scenario.onActivity {a->
    val p=player(a);p.selectCompatibleTrack(C.TRACK_TYPE_TEXT,p.compatibleTracks(C.TRACK_TYPE_TEXT).first().id)
    (a.javaClass.getDeclaredField("fullscreenDialog").apply{isAccessible=true}.get(a) as android.app.Dialog).dismiss()
   }
   SystemClock.sleep(700)
   scenario.onActivity {a->val box=a.javaClass.getDeclaredField("videoBox").apply{isAccessible=true}.get(a) as android.view.View;box.getGlobalVisibleRect(area);player(a).seekTo(11000)}
   SystemClock.sleep(1400)
   val returned=brightPixels()
   device.takeScreenshot(java.io.File("/sdcard/Pictures/TogetherUITests/$asset-returned.png"))
   assertTrue("Subtitle lost after leaving fullscreen: on=$returned rect=$area",returned>100)
   scenario.onActivity {a->assertTrue(player(a).selectedCompatibleTrack(C.TRACK_TYPE_TEXT)>=0);player(a).pause()}


  }} finally {file.delete()}
 }
}
