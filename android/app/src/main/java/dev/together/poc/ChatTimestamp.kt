package dev.together.poc

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Display the server's Unix-millisecond message timestamp in local time. */
object ChatTimestamp {
 fun label(timestampMs:Double,nowMs:Long=System.currentTimeMillis(),zone:TimeZone=TimeZone.getDefault()):String {
  if(!timestampMs.isFinite() || timestampMs<=0 || timestampMs>=253402300799000.0)return ""
  val stamp=Calendar.getInstance(zone).apply {timeInMillis=timestampMs.toLong()}
  val now=Calendar.getInstance(zone).apply {timeInMillis=nowMs}
  fun sameDay(a:Calendar,b:Calendar):Boolean =
    a.get(Calendar.ERA)==b.get(Calendar.ERA) &&
    a.get(Calendar.YEAR)==b.get(Calendar.YEAR) &&
    a.get(Calendar.DAY_OF_YEAR)==b.get(Calendar.DAY_OF_YEAR)
  val today=sameDay(stamp,now)
  val yesterday=now.clone() as Calendar
  yesterday.add(Calendar.DAY_OF_YEAR,-1)
  val wasYesterday=!today && sameDay(stamp,yesterday)
  val pattern=when {
   today || wasYesterday -> "HH:mm"
   stamp.get(Calendar.YEAR)==now.get(Calendar.YEAR) -> "M月d日 HH:mm"
   else -> "yyyy年M月d日 HH:mm"
  }
  val formatted=SimpleDateFormat(pattern,Locale.CHINA).apply{timeZone=zone}.format(Date(timestampMs.toLong()))
  return if(wasYesterday)"昨天 $formatted" else formatted
 }
}
