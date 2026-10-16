package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class FilmRecapCollectorTest {
 @Test fun orderedOnlyAfterCompleteNeverLeakingPartialSolutions() {
  val parser=FilmRecapCollector()
  val id="a".repeat(32)
  assertNull(parser.consume("bank-final:$id:1","🎬 片尾结算（2/3）\n正确答案：线索B"))
  assertNull(parser.latest)
  assertNull(parser.consume("bank-final:$id:0","🎬 片尾结算（1/3）\n观影结算\n"))
  assertNull(parser.consume("bank-final:$id:0","🎬 片尾结算（1/3）\n重复不能完成"))
  val result=parser.consume("bank-final:$id:2","🎬 片尾结算（3/3）\n最终成绩")
  assertNotNull(result)
  assertEquals("观影结算\n正确答案：线索B最终成绩",result!!.text)
  assertNull(parser.consume("bank-final:$id:2","🎬 片尾结算（3/3）\n不重复"))
 }
 @Test fun rejectsMalformedOrUntrustedShapes() {
  val parser=FilmRecapCollector()
  val id="b".repeat(32)
  assertNull(parser.consume("another:$id:0","🎬 片尾结算（1/1）\nsecret"))
  assertNull(parser.consume("bank-final:$id:0","🎬 片尾结算（3/1）\nsecret"))
  assertNull(parser.consume("bank-final:$id:99","🎬 片尾结算（100/2）\nsecret"))
  assertNull(parser.consume("bank-final:$id:0","🎬 片尾结算（1/101）\nsecret"))
  assertNull(parser.latest)
  assertNotNull(parser.consume("bank-final:$id:0","🎬 片尾结算（1/1）\n正确答案"))
  parser.clear()
  assertNull(parser.latest)
 }
}
