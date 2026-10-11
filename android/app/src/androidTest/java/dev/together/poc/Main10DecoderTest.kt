package dev.together.poc
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

@RunWith(AndroidJUnit4::class)
class Main10DecoderTest {
 @Test fun independentDecoderDisplaysActual4KMain10Frames() {
  val i=InstrumentationRegistry.getInstrumentation();val file=java.io.File(i.targetContext.cacheDir,"4k-main10-probe.mp4")
  i.context.assets.open("hevc-main10-4k-test.mp4").use {s->file.outputStream().use {s.copyTo(it)}}
  var core:LibVLC?=null;var player:MediaPlayer?=null;var media:Media?=null;var failed=false;var displayed=0
  try {ActivityScenario.launch(MainActivity::class.java).use {scenario->
   scenario.onActivity {activity->
    core=LibVLC(activity,arrayListOf("--no-video-title-show","--no-audio"));player=MediaPlayer(core!!)
    val layout=VLCVideoLayout(activity);activity.setContentView(layout);player!!.attachViews(layout,null,false,false)
    media=Media(core!!,android.net.Uri.fromFile(file));media!!.setHWDecoderEnabled(false,false);media!!.addOption(":codec=avcodec")
    player!!.setEventListener {if(it.type==MediaPlayer.Event.EncounteredError)failed=true}
    player!!.media=media;player!!.play()
   }
   val deadline=android.os.SystemClock.elapsedRealtime()+45000
   while(displayed==0 && !failed && android.os.SystemClock.elapsedRealtime()<deadline){scenario.onActivity {displayed=media?.stats?.displayedPictures ?: 0};android.os.SystemClock.sleep(100)}
   assertFalse("Independent HEVC decoder rejected Main10",failed)
   assertTrue("No real 4K Main10 video frame was displayed",displayed>0)
   scenario.onActivity {assertTrue(media!!.stats!!.decodedVideo>0)}
  }} finally {i.runOnMainSync {player?.stop();player?.detachViews();player?.release();media?.release();core?.release()};file.delete()}
 }
}
