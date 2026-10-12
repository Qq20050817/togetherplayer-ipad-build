package dev.together.poc
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.view.MotionEvent
import android.app.Dialog
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
@RunWith(AndroidJUnit4::class)
class FullscreenGestureTest {
 @Test fun holdReleaseCancellationAndBrightnessSlideAreDistinct(){
  val i=InstrumentationRegistry.getInstrumentation();val events=mutableListOf<Boolean>()
  ActivityScenario.launch(MainActivity::class.java).use{scenario->
   lateinit var view:FullscreenGestureView;lateinit var dialog:Dialog
   scenario.onActivity{a->dialog=Dialog(a);view=FullscreenGestureView(a,dialog,{events.add(it)},{ });dialog.setContentView(view);dialog.show();view.layout(0,0,1000,800)}
   fun touch(action:Int,x:Float,y:Float){i.runOnMainSync{val e=MotionEvent.obtain(0,android.os.SystemClock.uptimeMillis(),action,x,y,0);view.onTouchEvent(e);e.recycle()}}
   touch(MotionEvent.ACTION_DOWN,200f,400f);Thread.sleep(500);i.runOnMainSync{assertEquals(listOf(true),events)}
   touch(MotionEvent.ACTION_UP,200f,400f);i.runOnMainSync{assertEquals(listOf(true,false),events);events.clear()}
   touch(MotionEvent.ACTION_DOWN,200f,600f);touch(MotionEvent.ACTION_MOVE,200f,200f);Thread.sleep(400)
   i.runOnMainSync{assertTrue(events.isEmpty());assertTrue(dialog.window!!.attributes.screenBrightness>0)}
   touch(MotionEvent.ACTION_CANCEL,200f,200f)
   touch(MotionEvent.ACTION_DOWN,200f,400f);Thread.sleep(500);touch(MotionEvent.ACTION_CANCEL,200f,400f)
   i.runOnMainSync{assertEquals(listOf(true,false),events);dialog.dismiss()}
  }
 }
}
