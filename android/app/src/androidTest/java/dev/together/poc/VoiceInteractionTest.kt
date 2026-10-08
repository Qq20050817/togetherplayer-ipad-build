package dev.together.poc
import android.Manifest
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceInteractionTest {
 @Test fun offlineMicrophoneStartsAndStopsWithoutSendingOrPausingMovie() {
  val instrumentation=InstrumentationRegistry.getInstrumentation()
  val context=instrumentation.targetContext
  context.getSharedPreferences("MainActivity",0).edit().clear().commit()
  instrumentation.uiAutomation.grantRuntimePermission(context.packageName,Manifest.permission.RECORD_AUDIO)
  val movie=java.io.File(context.cacheDir,"voice-playback-test.mp4")
  instrumentation.context.assets.open("voice-playback-test.mp4").use {source->movie.outputStream().use {source.copyTo(it)}}
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   lateinit var voice:VoiceDanmakuController;lateinit var player:ExoPlayer
   var sent=0
   scenario.onActivity {activity->
    player=activity.javaClass.getDeclaredField("player").apply {isAccessible=true}.get(activity) as ExoPlayer
    player.volume=0.8f;player.repeatMode=androidx.media3.common.Player.REPEAT_MODE_ONE;player.setMediaItem(androidx.media3.common.MediaItem.fromUri(android.net.Uri.fromFile(movie)));player.prepare();player.play()
    voice=VoiceDanmakuController(activity,player,{"test-room"},{sent++;true},{})
    voice.enable()
   }
   val until=SystemClock.elapsedRealtime()+60000
   while(SystemClock.elapsedRealtime()<until){var ready=false;scenario.onActivity {ready=voice.state==VoiceDanmakuController.State.READY};if(ready)break;SystemClock.sleep(200)}
   scenario.onActivity {assertEquals(voice.status,VoiceDanmakuController.State.READY,voice.state);player.seekTo(1000);voice.begin()}
   SystemClock.sleep(1000)
   scenario.onActivity {assertEquals(voice.status,VoiceDanmakuController.State.RECORDING,voice.state);assertTrue(player.playWhenReady);assertTrue(player.isPlaying);assertTrue(player.currentPosition>1200);assertTrue(player.volume<0.8f);assertEquals(0,sent);voice.setUserVolume(0.4f);voice.release()}
   SystemClock.sleep(1000)
   scenario.onActivity {assertTrue(player.playWhenReady);assertEquals(0.4f,player.volume,0.01f);assertEquals(0,sent);assertNotEquals(VoiceDanmakuController.State.RECORDING,voice.state);voice.disable();assertEquals(VoiceDanmakuController.State.DISABLED,voice.state);voice.close()}
  }
 }
 @Test fun buttonUnavailableOutsideRoomDoesNotAskForMicrophone() {
  val context=InstrumentationRegistry.getInstrumentation().targetContext
  context.getSharedPreferences("MainActivity",0).edit().clear().commit()
  ActivityScenario.launch(MainActivity::class.java).use {scenario->scenario.onActivity {activity->
   val voice=activity.javaClass.getDeclaredField("voice").apply {isAccessible=true}.get(activity) as VoiceDanmakuController
   assertEquals(VoiceDanmakuController.State.DISABLED,voice.state)
  }}
 }
}
