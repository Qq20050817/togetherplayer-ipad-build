package dev.together.poc

object VideoRotation {
 fun normalized(turns:Int)=((turns%4)+4)%4
 fun next(turns:Int)=(normalized(turns)+1)%4
 fun degrees(turns:Int)=normalized(turns)*90
 fun childSize(width:Int,height:Int,turns:Int):Pair<Int,Int> =
  if(normalized(turns)%2==0)width to height else height to width
}
