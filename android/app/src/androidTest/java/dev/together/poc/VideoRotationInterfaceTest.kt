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
   var rendered=false
   var originalPlayer:androidx.media3.common.Player?=null
   val context=instrumentation.targetContext
   val fixture=File(context.cacheDir,"rotation-pattern.mp4")
   instrumentation.context.assets.open("rotation-pattern.mp4").use{input->fixture.outputStream().use{input.copyTo(it)}}
   scenario.onActivity {a->
    original=layer(a.window.decorView);assertNotNull(original);native=original!!.getChildAt(0) as PlayerView
    originalPlayer=native!!.player
    native!!.player!!.addListener(object:androidx.media3.common.Player.Listener {override fun onRenderedFirstFrame(){rendered=true}})
    native!!.player!!.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(fixture)));native!!.player!!.prepare();native!!.player!!.play()
   }
   var playing=false
   for(attempt in 0..25){scenario.onActivity{playing=native!!.player!!.isPlaying && rendered};if(playing)break;android.os.SystemClock.sleep(200)}
   assertTrue("Actual video fixture must render its first frame",playing)
   onView(allOf(withContentDescription("旋转画面"),isDisplayed())).perform(click())
   android.os.SystemClock.sleep(800)
   val area=IntArray(4)
   scenario.onActivity {
    assertEquals(1,original!!.quarterTurns);native=original!!.getChildAt(0) as PlayerView;assertSame(originalPlayer,native!!.player)
    original!!.getLocationOnScreen(area);area[2]=original!!.width;area[3]=original!!.height
   }
   assertTrue("Video layout must have nonzero dimensions",area[2]>0 && area[3]>0)
   val pictureHeight=minOf(area[3].toDouble(),area[2]*16.0/9)
   val pictureWidth=pictureHeight*9/16
   val x=area[0]+(area[2]-pictureWidth)/2;val y=area[1]+(area[3]-pictureHeight)/2
   var screenshot:Bitmap?=null
   var colors=IntArray(4)
   var correct=false
   for(attempt in 0..20) {
    val shot=instrumentation.uiAutomation.takeScreenshot();screenshot=shot
    fun pixel(fx:Double,fy:Double)=shot.getPixel((x+pictureWidth*fx).toInt(),(y+pictureHeight*fy).toInt())
    colors=intArrayOf(pixel(0.3,0.35),pixel(0.7,0.35),pixel(0.3,0.65),pixel(0.7,0.65))
    val(tl,tr,bl,br)=colors
    correct=Color.blue(tl)>Color.red(tl)+40 && Color.blue(tl)>Color.green(tl)+40 &&
     Color.red(tr)>Color.blue(tr)+40 && Color.red(tr)>Color.green(tr)+40 &&
     Color.red(bl)>130 && Color.green(bl)>130 && Color.blue(bl)<100 &&
     Color.green(br)>Color.red(br)+40 && Color.green(br)>Color.blue(br)+40
    if(correct)break
    android.os.SystemClock.sleep(250)
   }
   val bytes=java.io.ByteArrayOutputStream();screenshot!!.compress(Bitmap.CompressFormat.PNG,100,bytes)
   File(context.getExternalFilesDir(null),"rotation-90.png").writeBytes(bytes.toByteArray())
   val crop=java.io.ByteArrayOutputStream()
   Bitmap.createBitmap(screenshot!!,area[0],area[1],area[2],area[3]).compress(Bitmap.CompressFormat.PNG,100,crop)
   val evidence=if(correct)"" else " ROTATION_IMAGE="+android.util.Base64.encodeToString(crop.toByteArray(),android.util.Base64.NO_WRAP)
   assertTrue("90-degree video quadrants must be blue/red/yellow/green; area="+area.joinToString()+", samples="+colors.joinToString{Integer.toHexString(it)}+evidence,correct)
   onView(allOf(withContentDescription("全屏"),isDisplayed())).perform(click())
   println("ROTATION: rendered quadrant checks passed; entering fullscreen")
   onView(withText("导入字幕")).inRoot(isDialog()).check(doesNotExist())
   onView(withText("旋转画面")).inRoot(isDialog()).perform(click())
   scenario.onActivity {assertEquals(2,original!!.quarterTurns);native=original!!.getChildAt(0) as PlayerView;assertSame(originalPlayer,native!!.player)}
   println("ROTATION: fullscreen rotation passed")
   pressBack()
   onView(allOf(withContentDescription("旋转画面"),isDisplayed())).perform(click())
   onView(allOf(withContentDescription("旋转画面"),isDisplayed())).perform(click())
   scenario.onActivity {assertEquals(0,original!!.quarterTurns);native=original!!.getChildAt(0) as PlayerView;assertSame(originalPlayer,native!!.player);assertTrue(native!!.player!!.currentPosition>0)}
   onView(allOf(withContentDescription("字幕"),isDisplayed())).perform(click())
   onView(withText("导入外挂字幕（SRT / VTT / ASS）")).inRoot(isDialog()).check(matches(isDisplayed()))
   pressBack()
   fixture.delete()
  }
 }
}
