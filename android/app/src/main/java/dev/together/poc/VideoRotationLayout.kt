package dev.together.poc

import android.content.Context
import android.view.View
import android.widget.FrameLayout

// Only renderer children enter this layer. Controls, external captions and
// native text subtitle overlays stay in the stationary outer videoBox.
class VideoRotationLayout(context:Context):FrameLayout(context) {
 var quarterTurns=0
  set(value){val n=VideoRotation.normalized(value);if(field!=n){field=n;requestLayout()}}
 init {clipChildren=true;clipToPadding=true;contentDescription="视频画面"}
 override fun onMeasure(widthMeasureSpec:Int,heightMeasureSpec:Int) {
  val w=View.MeasureSpec.getSize(widthMeasureSpec)
  val h=View.MeasureSpec.getSize(heightMeasureSpec)
  setMeasuredDimension(w,h)
  val size=VideoRotation.childSize(w,h,quarterTurns)
  for(i in 0 until childCount)getChildAt(i).measure(View.MeasureSpec.makeMeasureSpec(size.first,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(size.second,View.MeasureSpec.EXACTLY))
 }
 override fun onLayout(changed:Boolean,left:Int,top:Int,right:Int,bottom:Int) {
  val w=right-left;val h=bottom-top
  for(i in 0 until childCount) {
   val child=getChildAt(i);val cw=child.measuredWidth;val ch=child.measuredHeight
   val x=(w-cw)/2;val y=(h-ch)/2
   child.layout(x,y,x+cw,y+ch)
   child.pivotX=cw/2f;child.pivotY=ch/2f
   child.rotation=VideoRotation.degrees(quarterTurns).toFloat()
  }
  contentDescription="视频画面 "+VideoRotation.degrees(quarterTurns)+"°"
 }
}
