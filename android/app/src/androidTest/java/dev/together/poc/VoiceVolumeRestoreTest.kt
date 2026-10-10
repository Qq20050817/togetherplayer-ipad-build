package dev.together.poc

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceVolumeRestoreTest {
 @Test fun repeatedFinishAndRapidPressRestoreUsersVolume() {
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   fun change(block:(VoiceDanmakuController,ExoPlayer)->Unit) {
    scenario.onActivity {activity->
     val voice=activity.javaClass.getDeclaredField("voice").apply{isAccessible=true}.get(activity) as VoiceDanmakuController
     val player=activity.javaClass.getDeclaredField("player").apply{isAccessible=true}.get(activity) as ExoPlayer
     block(voice,player)
    }
   }
   fun duck(voice:VoiceDanmakuController,lower:Boolean) {
    voice.javaClass.getDeclaredMethod("duck",Boolean::class.javaPrimitiveType).apply{isAccessible=true}.invoke(voice,lower)
   }
   change {voice,_->voice.setUserVolume(0.8f);duck(voice,true)}
   Thread.sleep(600)
   change {voice,_->duck(voice,false);duck(voice,false)}
   Thread.sleep(600)
   change {voice,player->assertEquals(0.8f,player.volume,0.001f);duck(voice,true)}
   Thread.sleep(600)
   change {voice,_->duck(voice,false)}
   Thread.sleep(60)
   change {voice,_->duck(voice,true);duck(voice,false)}
   Thread.sleep(600)
   change {voice,player->assertEquals(0.8f,voice.userVolume,0.001f);assertEquals(0.8f,player.volume,0.001f)}
  }
 }
}
