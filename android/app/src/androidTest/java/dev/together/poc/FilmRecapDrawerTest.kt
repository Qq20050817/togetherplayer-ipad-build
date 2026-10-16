package dev.together.poc

import android.app.Dialog
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FilmRecapDrawerTest {
 private fun field(a:MainActivity,name:String)=a.javaClass.getDeclaredField(name).apply{isAccessible=true}

 @Test fun endOfStoryOpensQuestionStyleDrawerBesideMovieWithoutChatSpoilers() {
  val instrument=InstrumentationRegistry.getInstrumentation()
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   scenario.onActivity {a->
    val fragments=field(a,"filmRecap").get(a) as FilmRecapCollector
    val id="e".repeat(32)
    assertNull(fragments.consume("bank-final:$id:0","🎬 片尾结算（1/2）\n🎬 电影观影结算\n"))
    assertNotNull(fragments.consume("bank-final:$id:1","🎬 片尾结算（2/2）\n正确答案：证人有意隐瞒"))
    a.javaClass.getDeclaredMethod("showFullscreen").apply{isAccessible=true}.invoke(a)
    a.javaClass.getDeclaredMethod("showFilmRecap").apply{isAccessible=true}.invoke(a)
   }
   val device=UiDevice.getInstance(instrument)
   assertNotNull("The same side drawer must show the final answer",device.wait(Until.findObject(By.textContains("正确答案：证人有意隐瞒")),5000))
   scenario.onActivity {a->
    val drawer=field(a,"plotDrawer").get(a) as Dialog
    val movie=field(a,"videoBox").get(a) as View
    val movieAt=IntArray(2);val drawerAt=IntArray(2)
    movie.getLocationOnScreen(movieAt)
    drawer.window!!.decorView.getLocationOnScreen(drawerAt)
    assertTrue("The report must sit beside the film like a poll",movieAt[0]+movie.width<=drawerAt[0]+2)
    val chat=field(a,"chat").get(a) as ChatEngine
    assertTrue("Raw answer keys must not be normal chat messages",chat.messages.isEmpty())
    drawer.dismiss()
   }
   instrument.waitForIdleSync()
   scenario.onActivity {a->(field(a,"fullscreenDialog").get(a) as Dialog).dismiss()}
  }
 }
}
