package dev.together.poc
import android.view.View
import android.view.ViewGroup
import android.graphics.Color
import android.graphics.Bitmap
import androidx.media3.common.MediaItem
import androidx.media3.ui.PlayerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.Espresso.pressBack
import androidx.test.espresso.matcher.RootMatchers.isDialog
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.assertion.ViewAssertions.*
import androidx.test.espresso.matcher.ViewMatchers.*
import org.hamcrest.Matchers.allOf
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class VideoRotationInterfaceTest {
 private fun layer(v:View):VideoRotationLayout? {
  if(v is VideoRotationLayout)return v
  if(v is ViewGroup)for(i in 0 until v.childCount){val found=layer(v.getChildAt(i));if(found!=null)return found}
  return null
 }
 @Test fun rotationKeepsRendererAndFullscreenStateAndConsolidatesImport() {
  val instrumentation=InstrumentationRegistry.getInstrumentation()
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   var original:VideoRotationLayout?=null
   var native:PlayerView?=null
   val context=instrumentation.targetContext
   val fixture=File(context.cacheDir,"rotation-pattern.mp4")
   instrumentation.context.assets.open("rotation-pattern.mp4").use{input->fixture.outputStream().use{input.copyTo(it)}}
   scenario.onActivity {a->
    original=layer(a.window.decorView);assertNotNull(original);native=original!!.getChildAt(0) as PlayerView
    native!!.player!!.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(fixture)));native!!.player!!.prepare();native!!.player!!.play()
   }
   var playing=false
   for(attempt in 0..25){scenario.onActivity{playing=native!!.player!!.isPlaying};if(playing)break;android.os.SystemClock.sleep(200)}
   assertTrue("Actual video fixture must start",playing)
   onView(allOf(withContentDescription("旋转画面"),isDisplayed())).perform(click())
   android.os.SystemClock.sleep(800)
   val area=IntArray(4)
   scenario.onActivity {
    assertEquals(1,original!!.quarterTurns);assertSame(native,original!!.getChildAt(0))
    original!!.getLocationOnScreen(area);area[2]=original!!.width;area[3]=original!!.height
   }
   val screenshot=instrumentation.uiAutomation.takeScreenshot()
   File(context.getExternalFilesDir(null),"rotation-90.png").outputStream().use{screenshot.compress(Bitmap.CompressFormat.PNG,100,it)}
   val pictureHeight=minOf(area[3].toDouble(),area[2]*16.0/9)
   val pictureWidth=pictureHeight*9/16
   val x=area[0]+(area[2]-pictureWidth)/2;val y=area[1]+(area[3]-pictureHeight)/2
   fun pixel(fx:Double,fy:Double)=screenshot.getPixel((x+pictureWidth*fx).toInt(),(y+pictureHeight*fy).toInt())
   val tl=pixel(0.3,0.35);val tr=pixel(0.7,0.35);val bl=pixel(0.3,0.65);val br=pixel(0.7,0.65)
   assertTrue("90° top-left must be blue",Color.blue(tl)>Color.red(tl)+40 && Color.blue(tl)>Color.green(tl)+40)
   assertTrue("90° top-right must be red",Color.red(tr)>Color.blue(tr)+40 && Color.red(tr)>Color.green(tr)+40)
   assertTrue("90° bottom-left must be yellow",Color.red(bl)>130 && Color.green(bl)>130 && Color.blue(bl)<100)
   assertTrue("90° bottom-right must be green",Color.green(br)>Color.red(br)+40 && Color.green(br)>Color.blue(br)+40)
   onView(allOf(withContentDescription("全屏"),isDisplayed())).perform(click())
   println("ROTATION: rendered quadrant checks passed; entering fullscreen")
   onView(withText("导入字幕")).inRoot(isDialog()).check(doesNotExist())
   onView(withText("旋转画面")).inRoot(isDialog()).perform(click())
   scenario.onActivity {assertEquals(2,original!!.quarterTurns);assertSame(native,original!!.getChildAt(0))}
   println("ROTATION: fullscreen rotation passed")
   pressBack()
   onView(allOf(withContentDescription("旋转画面"),isDisplayed())).perform(click())
   onView(allOf(withContentDescription("旋转画面"),isDisplayed())).perform(click())
   scenario.onActivity {assertEquals(0,original!!.quarterTurns);assertSame(native,original!!.getChildAt(0));assertTrue(native!!.player!!.currentPosition>0)}
   onView(allOf(withContentDescription("字幕"),isDisplayed())).perform(click())
   onView(withText("导入外挂字幕（SRT / VTT / ASS）")).inRoot(isDialog()).check(matches(isDisplayed()))
   pressBack()
   fixture.delete()
  }
 }
}
