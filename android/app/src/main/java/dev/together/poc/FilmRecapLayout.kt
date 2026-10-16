package dev.together.poc

// Presentation parser for the existing final-only chat-fragment protocol.
// Keep legacy 0.6.9 reports readable; optional filmReview uses visible
// section markers appended only after the end of the story.
data class FilmRecapCard(
 val heading:String,
 val votes:List<String>,
 val correct:String?,
 val evidence:List<String>,
 val explanation:String,
 val wrong:Boolean,
 val right:Boolean
)
data class FilmRecapViewModel(
 val heading:String,
 val stats:String,
 val score:String,
 val total:Int,
 val completed:Int,
 val cards:List<FilmRecapCard>,
 val plotBeats:List<Pair<String,String>>,
 val people:List<Pair<String,String>>,
 val theme:String,
 val discussion:String
)
object FilmRecapLayout {
 fun parse(report:String):FilmRecapViewModel {
  val pair=report.split("\n🎞 全片复盘\n",limit=2)
  val chunks=pair[0].split("\n第")
  val head=chunks.first().lines().filter{it.isNotBlank()}
  val stats=head.firstOrNull{it.startsWith("本轮发题 ")}.orEmpty()
  val number=Regex("本轮发题 (\\d+) 道，完成 (\\d+) 道").find(stats)
  val cards=chunks.drop(1).map { piece->
   val entries=("第"+piece).lines().filter{it.isNotBlank()}
   val answer=entries.firstOrNull{it.startsWith("正确答案：")}
   val evidence=entries.filter{it.startsWith("关键证据：")}.map{it.removePrefix("关键证据：")}
   val expl=entries.firstOrNull{it.startsWith("剧情解析：")}?.removePrefix("剧情解析：").orEmpty()
   val votes=entries.filter{
    (it.contains("：") && !it.startsWith("第") && !it.startsWith("正确答案：") &&
     !it.startsWith("关键证据：") && !it.startsWith("剧情解析：") &&
     !it.startsWith("本轮答案") && !it.startsWith("成绩："))
   }
   FilmRecapCard(entries.firstOrNull().orEmpty(),votes,answer, evidence, expl,
    votes.any{it.endsWith(" ✗")},votes.any{it.endsWith(" ✓")})
  }
  val review=pair.getOrNull(1)?.lines().orEmpty()
  fun segments(tag:String)=review.filter{it.startsWith(tag)}.map {
   val sections=it.removePrefix(tag).split("｜")
   Pair(if(sections.size>=3) sections[1] else sections.first(), sections.last())
  }
  return FilmRecapViewModel(
   heading=head.firstOrNull().orEmpty(),stats=stats,
   score=head.firstOrNull{it.startsWith("成绩：")}.orEmpty(),
   total=number?.groupValues?.get(1)?.toIntOrNull() ?: 0,
   completed=number?.groupValues?.get(2)?.toIntOrNull() ?: 0,
   cards=cards,
   plotBeats=segments("剧情节点："),
   people=segments("人物关系："),
   theme=review.firstOrNull{it.startsWith("主题解读：")}?.removePrefix("主题解读：").orEmpty(),
   discussion=review.firstOrNull{it.startsWith("观后讨论：")}?.removePrefix("观后讨论：").orEmpty()
  )
 }
}
