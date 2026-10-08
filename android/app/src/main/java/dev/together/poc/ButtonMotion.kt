package dev.together.poc
import android.view.MotionEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
/** Visual feedback only: return false to keep click/accessibility dispatch immediate. */
object ButtonMotion {
 fun install(view:View) {view.setOnTouchListener {_,event->
  if(view.isEnabled)when(event.actionMasked){
   MotionEvent.ACTION_DOWN->animate(view,true)
   MotionEvent.ACTION_UP,MotionEvent.ACTION_CANCEL->animate(view,false)
  }
  false
 }}
 private fun animate(view:View,pressed:Boolean){
  view.animate().cancel()
  view.animate().scaleX(if(pressed)0.96f else 1f).scaleY(if(pressed)0.96f else 1f).alpha(if(pressed)0.72f else 1f)
   .setDuration(if(pressed)70 else 140).setInterpolator(DecelerateInterpolator()).start()
 }
}
