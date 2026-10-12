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
 @Test fun windowDispatchChangesBrightness() {
  val instrumentation=InstrumentationRegistry.getInstrumentation()
  lateinit var dialog:Dialog;lateinit var view:FullscreenGestureView
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   scenario.onActivity {activity->
    dialog=Dialog(activity,android.R.style.Theme_Black_NoTitleBar_Fullscreen)
    view=FullscreenGestureView(activity,dialog,{},{})
    dialog.setContentView(view);dialog.show();dialog.window!!.setLayout(800,600)
    val params=dialog.window!!.attributes
    params.screenBrightness=0.8f
    dialog.window!!.attributes=params
   }
   instrumentation.waitForIdleSync()
   val startTime=android.os.SystemClock.uptimeMillis()
   fun send(action:Int,xFraction:Float,yFraction:Float,delay:Long){
    instrumentation.runOnMainSync {
     val loc=IntArray(2);view.getLocationInWindow(loc)
     val e=MotionEvent.obtain(startTime,startTime+delay,action,loc[0]+view.width*xFraction,loc[1]+view.height*yFraction,0)
     assertTrue("Fullscreen dialog must dispatch touch events",dialog.window!!.decorView.dispatchTouchEvent(e))
     e.recycle()
    }
   }
   send(MotionEvent.ACTION_DOWN,0.2f,0.2f,0)
   send(MotionEvent.ACTION_MOVE,0.2f,0.65f,40)
   instrumentation.runOnMainSync {
    assertTrue("Fullscreen brightness must visibly change after a real window swipe",dialog.window!!.attributes.screenBrightness<0.65f)
   }
   send(MotionEvent.ACTION_UP,0.2f,0.65f,80)
   instrumentation.runOnMainSync {dialog.dismiss()}
  }
 }
 @Test fun holdReleaseCancellationAndBrightnessSlideAreDistinct(){
  val i=InstrumentationRegistry.getInstrumentation();val events=mutableListOf<Boolean>()
  ActivityScenario.launch(MainActivity::class.java).use{scenario->
   lateinit var view:FullscreenGestureView;lateinit var dialog:Dialog
   scenario.onActivity{a->dialog=Dialog(a);view=FullscreenGestureView(a,dialog,{events.add(it)},{ });dialog.setContentView(view);dialog.show();dialog.window!!.setLayout(1000,800);view.layout(0,0,1000,800)}
   fun touch(action:Int,x:Float,y:Float){i.runOnMainSync{val e=MotionEvent.obtain(0,android.os.SystemClock.uptimeMillis(),action,x,y,0);view.onTouchEvent(e);e.recycle()}}
   touch(MotionEvent.ACTION_DOWN,200f,400f);Thread.sleep(500);i.runOnMainSync{assertEquals(listOf(true),events)}
   touch(MotionEvent.ACTION_UP,200f,400f);i.runOnMainSync{assertEquals(listOf(true,false),events);events.clear()}
   touch(MotionEvent.ACTION_DOWN,200f,600f);touch(MotionEvent.ACTION_MOVE,200f,200f);Thread.sleep(400)
   i.runOnMainSync{assertTrue(events.isEmpty());assertTrue(dialog.window!!.attributes.screenBrightness>0)}
   touch(MotionEvent.ACTION_CANCEL,200f,200f)
   val audio=i.targetContext.getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
   val oldVolume=audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
   i.runOnMainSync{audio.setStreamVolume(android.media.AudioManager.STREAM_MUSIC,1,0)}
   touch(MotionEvent.ACTION_DOWN,800f,600f);touch(MotionEvent.ACTION_MOVE,800f,200f);touch(MotionEvent.ACTION_UP,800f,200f)
   i.runOnMainSync{assertTrue(audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)>1);audio.setStreamVolume(android.media.AudioManager.STREAM_MUSIC,oldVolume,0)}
   touch(MotionEvent.ACTION_DOWN,200f,400f);Thread.sleep(500);touch(MotionEvent.ACTION_CANCEL,200f,400f)
   i.runOnMainSync{assertEquals(listOf(true,false),events);dialog.dismiss()}
  }
 }
}
