package dev.together.poc
object DanmakuSpeed {
 fun duration(base:Long,speed:Float):Long {
  val value=if(speed.isFinite() && speed>0)speed.coerceIn(0.5f,2f)else 1f
  return (base/value).toLong()
 }
}
