package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class PlotPollPresentationTest {
 @Test fun wholeQuestionAppearsInBodyAndTitleStaysShort() {
  val long="听到甲板上没有人，又听到有人寻找朋友之后，下一步最可能发生什么？哪条线索更值得双方继续观察？"
  val heading=PlotPollPresentation.title("剧情预测",46,53)
  assertEquals("🎭 剧情预测 · 46:53",heading)
  assertFalse(heading.contains(long))
  val body=PlotPollPresentation.questionBody(true,long)
  assertTrue(body.contains(long))
  assertTrue(body.contains("双方提交"))
  assertTrue(body.contains("真正看过"))
 }
 @Test fun emptyQuestionIsHandledInsteadOfInvisibleDialog() {
  assertTrue(PlotPollPresentation.questionBody(false," ").contains("请稍后"))
  assertEquals("🎭 说法矛盾 · 5:07",PlotPollPresentation.title("说法矛盾",5,7))
 }
}
