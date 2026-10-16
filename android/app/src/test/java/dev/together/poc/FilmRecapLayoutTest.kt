package dev.together.poc

import org.junit.Assert.*
import org.junit.Test

class FilmRecapLayoutTest {
 @Test fun parsesVisualScoreEvidenceAndFilmReview() {
  val report = listOf(
   "🎬 电影观影结算 · 悬疑样片",
   "本轮发题 2 道，完成 2 道。",
   "成绩：甲 1/2 · 乙 2/2",
   "",
   "第1题：谁保留了证据？",
   "甲：警探 ✗",
   "乙：证人 ✓",
   "正确答案：证人",
   "关键证据：摄像机记录证人带走钥匙",
   "剧情解析：监控揭示了真正的持有人。角色此时知道证人为何隐藏证据。",
   "",
   "第2题：你会如何选择？",
   "开放讨论题，无唯一标准答案。",
   "",
   "本轮答案与解析已统一公布，回看进度不会重新结算。",
   "",
   "🎞 全片复盘",
   "剧情节点：1｜谜团出现｜主角第一次发现关键物证",
   "剧情节点：2｜真相揭晓｜影像说明了动机",
   "人物关系：证人｜为了保护伙伴而隐瞒",
   "主题解读：电影通过多个角色的矛盾证词，强调直接证据与片面叙述之间的巨大差异。",
   "观后讨论：如果你是主角，你会优先审查哪一条证据？"
  ).joinToString("\n")
  val view=FilmRecapLayout.parse(report)
  assertEquals(2,view.total)
  assertEquals(2,view.completed)
  assertEquals(2,view.cards.size)
  assertTrue(view.cards[0].wrong)
  assertEquals("正确答案：证人",view.cards[0].correct)
  assertEquals("摄像机记录证人带走钥匙",view.cards[0].evidence.single())
  assertEquals(2,view.plotBeats.size)
  assertEquals("谜团出现",view.plotBeats.first().first)
  assertEquals("证人",view.people.single().first)
  assertTrue(view.theme.contains("证据"))
  assertTrue(view.discussion.contains("主角"))
 }
 @Test fun legacyRecapStillParsesWithoutFilmReview() {
  val report="🎬 电影观影结算 · 旧影片\n本轮发题 1 道，完成 1 道。\n第1题：线索是什么？\n正确答案：钥匙\n剧情解析：来自字幕证据"
  val view=FilmRecapLayout.parse(report)
  assertEquals(1,view.cards.size)
  assertTrue(view.plotBeats.isEmpty())
  assertEquals("",view.theme)
  assertEquals("正确答案：钥匙",view.cards[0].correct)
 }
}
