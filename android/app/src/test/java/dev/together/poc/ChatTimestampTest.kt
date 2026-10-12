package dev.together.poc

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class ChatTimestampTest {
 private val utc=TimeZone.getTimeZone("UTC")
 private fun ms(value:String):Long =
  SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss",Locale.US).apply{timeZone=utc}.parse(value)!!.time
 @Test fun displaysTodayYesterdayOtherDaysAndPreviousYear() {
  val now=ms("2026-10-13T01:20:00")
  fun label(value:String)=ChatTimestamp.label(ms(value).toDouble(),now,utc)
  assertEquals("00:05",label("2026-10-13T00:05:00"))
  assertEquals("昨天 23:40",label("2026-10-12T23:40:00"))
  assertEquals("10月11日 08:09",label("2026-10-11T08:09:00"))
  assertEquals("2025年12月31日 23:59",label("2025-12-31T23:59:00"))
  assertEquals("",ChatTimestamp.label(0.0,now,utc))
  assertEquals("",ChatTimestamp.label(Double.NaN,now,utc))
 }
}
