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
 @Test fun selectedEmbeddedSubtitleProducesVisiblePixels() {
  val i=InstrumentationRegistry.getInstrumentation();val file=java.io.File(i.targetContext.cacheDir,"embedded-subtitle.mkv")
  i.context.assets.open("embedded-subtitle.mkv").use {s->file.outputStream().use {s.copyTo(it)}}
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
   java.io.File("/sdcard/Pictures/TogetherUITests").mkdirs();device.takeScreenshot(java.io.File("/sdcard/Pictures/TogetherUITests/embedded-subtitle.png"))
   assertTrue("Selected embedded subtitle has no visible pixels: off=$closed on=$shown rect=$area",shown>closed+100)
   scenario.onActivity {a->assertTrue(player(a).selectedCompatibleTrack(C.TRACK_TYPE_TEXT)>=0);player(a).pause()}
  }} finally {file.delete()}
 }
}
