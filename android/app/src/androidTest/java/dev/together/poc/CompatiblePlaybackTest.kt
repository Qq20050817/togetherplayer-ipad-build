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
   scenario.onActivity {a->val p=playback(a);p.setMediaItem(MediaItem.fromUri(uri),0);assertTrue(p.activateCompatibility(uri,0));p.volume=.7f}
   var ready=false
   val deadline=SystemClock.elapsedRealtime()+45000
   while(!ready && SystemClock.elapsedRealtime()<deadline){scenario.onActivity {a->val p=playback(a);assertNull(p.playerError);ready=p.playbackState==Player.STATE_READY};SystemClock.sleep(100)}
   assertTrue("Integrated fallback did not display a real frame",ready)
   scenario.onActivity {a->val p=playback(a);assertTrue(p.displayedFrames()>0);assertTrue(p.decodedFrames()>0);assertTrue(p.duration>0);assertFalse("Preparing must not autoplay a paused room",p.playWhenReady);assertFalse(p.isPlaying);assertEquals(.7f,p.volume,.01f);p.volume=0f;assertEquals(0f,p.volume,.001f);p.seekTo(1000);assertEquals(1000,p.currentPosition);p.play();assertTrue(p.playWhenReady);p.pause();assertFalse(p.playWhenReady)}
   SystemClock.sleep(400)
   scenario.onActivity {a->val p=playback(a);assertFalse(p.isPlaying);p.setMediaItem(MediaItem.fromUri("https://example.invalid/next.mp4"),0);assertFalse(p.compatibleActive);assertFalse(p.activateCompatibility("https://example.invalid/next.mp4",0));p.clearMediaItems()}
  }} finally {file.delete()}
 }
}
