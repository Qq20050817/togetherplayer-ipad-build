package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
import kotlin.random.Random

class SubtitleLookupPerformanceTest {
 @Test fun indexedLookupMatchesLinearReferenceAcrossOverlapsGapsAndSeeks() {
  val random=Random(654)
  val cues=List(1000){i->val start=random.nextLong(0,100000);SubtitleCue(start,start+random.nextLong(1,20000),"字幕 $i")}
  val subtitle=ExternalSubtitle(cues)
  repeat(2000){val position=random.nextLong(-1000,120000);val delay=random.nextLong(-5000,5000)
   val expected=cues.filter{position-delay>=it.start && position-delay<it.end}.joinToString("\n"){it.text}
   assertEquals(expected,subtitle.textAt(position,delay))
  }
 }
 @Test fun cueEndsAreExclusiveAndCallerMutationCannotInvalidateIndex() {
  val cues=mutableListOf(SubtitleCue(1000,3000,"你好"),SubtitleCue(2000,4000,"world"))
  val subtitle=ExternalSubtitle(cues);cues.clear()
  assertEquals("你好\nworld",subtitle.textAt(2000));assertEquals("world",subtitle.textAt(3000));assertEquals("",subtitle.textAt(4000))
  assertEquals("",ExternalSubtitle(emptyList()).textAt(1000))
 }
 @Test fun longMovieLookupBenchmarkReportsMeasuredCost() {
  val cues=List(30000){i->SubtitleCue(i*2000L,i*2000L+1500,"dialogue $i")};val subtitle=ExternalSubtitle(cues)
  val times=List(2000){i->((i*7919L)%60000000)}
  repeat(2){for(t in times)subtitle.textAt(t)}
  val indexedStart=System.nanoTime();val actual=times.map{subtitle.textAt(it)};val indexedNanos=System.nanoTime()-indexedStart
  val linearStart=System.nanoTime();val expected=times.map{time->cues.filter{time>=it.start && time<it.end}.joinToString("\n"){it.text}};val linearNanos=System.nanoTime()-linearStart
  assertEquals(expected,actual)
  println("Subtitle lookup: 30000 cues / 2000 seeks; indexed=${indexedNanos/1e6}ms; baseline-linear=${linearNanos/1e6}ms; JVM synthetic, not device FPS")
 }
}
