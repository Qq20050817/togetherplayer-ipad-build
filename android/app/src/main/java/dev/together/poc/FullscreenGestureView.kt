package dev.together.poc

import android.app.Dialog
import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import kotlin.math.abs

/** A movie-only surface. Sliders, tools and voice controls remain outside it. */
class FullscreenGestureView(context:Context,private val dialog:Dialog,private val hold:(Boolean)->Unit,private val tap:()->Unit):FrameLayout(context) {
 private val main=Handler(Looper.getMainLooper())
 private val audio=context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
 private val hint=TextView(context).apply {setTextColor(-1);textSize=16f;setPadding(16,8,16,8);setBackgroundColor(0x99000000.toInt());visibility=View.GONE}
 private var x=0f;private var y=0f;private var initial=0f;private var left=false
 private var tracking=false;private var sliding=false;private var holding=false;private var cancelled=false
 private val slop=android.view.ViewConfiguration.get(context).scaledTouchSlop
 private val startHold=Runnable {if(tracking && !sliding && !cancelled){holding=true;hold(true);hint.text="2× 双端倍速";hint.visibility=View.VISIBLE}}
 init {isClickable=true;contentDescription="全屏手势：左侧亮度，右侧音量，长按双端倍速";addView(hint,LayoutParams(-2,-2,android.view.Gravity.CENTER))}
 override fun onTouchEvent(e:MotionEvent):Boolean {
  when(e.actionMasked){
   MotionEvent.ACTION_DOWN->{tracking=true;sliding=false;holding=false;cancelled=false;x=e.x;y=e.y;left=x<width/2;initial=if(left)dialog.window?.attributes?.screenBrightness?.takeIf{it>=0} ?: (android.provider.Settings.System.getInt(context.contentResolver,android.provider.Settings.System.SCREEN_BRIGHTNESS,128)/255f) else audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat()/audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1);main.postDelayed(startHold,350);parent?.requestDisallowInterceptTouchEvent(true)}
   MotionEvent.ACTION_MOVE->{val dx=e.x-x;val dy=e.y-y
    if(!sliding && !cancelled && (abs(dx)>slop || abs(dy)>slop)) {main.removeCallbacks(startHold);if(holding){hold(false);holding=false};sliding=abs(dy)>abs(dx);cancelled=!sliding}
    if(sliding){val value=(initial-dy/height.coerceAtLeast(1)).coerceIn(0f,1f);if(left){dialog.window?.let{w->val attrs=w.attributes;attrs.screenBrightness=value.coerceAtLeast(0.01f);w.attributes=attrs}}else audio.setStreamVolume(AudioManager.STREAM_MUSIC,(value*audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt(),0);hint.text="${if(left)"亮度" else "音量"} ${(value*100).toInt()}%";hint.visibility=View.VISIBLE}
   }
   MotionEvent.ACTION_POINTER_DOWN,MotionEvent.ACTION_CANCEL->{finish()}
   MotionEvent.ACTION_UP->{if(!holding && !sliding && !cancelled)performClick();finish()}
  };return true
 }
 override fun performClick():Boolean {super.performClick();tap();return true}
 private fun finish(){main.removeCallbacks(startHold);if(holding)hold(false);holding=false;tracking=false;hint.visibility=View.GONE;parent?.requestDisallowInterceptTouchEvent(false)}
 override fun onDetachedFromWindow(){finish();super.onDetachedFromWindow()}
}
