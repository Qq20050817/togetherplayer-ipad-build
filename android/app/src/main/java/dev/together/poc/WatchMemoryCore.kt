package dev.together.poc

import java.util.Locale
data class MemoryFilm(val id:String,val title:String,val year:Int,val aliases:List<String>,val tags:List<String>,val synopsis:String,val sourceURL:String?=null)
data class MemoryRecord(val id:String,val title:String,val completedAt:Long,val rating:Int?=null,val tags:List<String> = emptyList(),val note:String="")
data class MemorySuggestion(val film:MemoryFilm,val reason:String,val connection:String)
object FilmTaste {
 val tags=listOf("悬疑","反转","低血腥","黑色幽默","喜剧","爱情","生活化","互怼","误会","轻松","温情","家庭","科幻","动画","韩国","现实题材","慢节奏","快节奏","心理","压抑","血腥")
 fun clean(raw:String):String=raw.substringAfterLast('/').replace(Regex("\\.(mkv|mp4|m4v|mov|avi|ts)$",RegexOption.IGNORE_CASE),"").replace(Regex("[ ._\\-\\[]+(?:2160p|1080p|720p|bluray|bdrip|remux|webrip|web-dl|x265|x264|hevc|hdr|dv)\\b.*$",RegexOption.IGNORE_CASE),"").replace('.',' ').replace('_',' ').trim()
 fun key(s:String)=s.lowercase(Locale.ROOT).filter{it.isLetterOrDigit()}
 fun match(title:String,catalog:List<MemoryFilm>):MemoryFilm? {
  val s=key(clean(title))
  return catalog.filter{f->(listOf(f.title)+f.aliases).any{val k=key(it);s==k || s==k+f.year || (k.length>=4 && s.startsWith(k+f.year))}}.singleOrNull()
 }
 fun suggestions(records:List<MemoryRecord>,catalog:List<MemoryFilm>,dismissed:Set<String>):List<MemorySuggestion> {
  if(records.isEmpty())return emptyList()
  val seen=records.map{it.id}.toSet();val weights=mutableMapOf<String,Double>()
  records.forEach{r->val w=r.rating?.let{(it-3).toDouble()}?:0.25;r.tags.toSet().forEach{weights[it]=(weights[it]?:0.0)+w}}
  return catalog.filter{f->f.id !in seen && f.id !in dismissed && records.none{(it.id.startsWith("title:") && key(clean(it.title))==key(f.title))}}.map{f->
   val shared=f.tags.filter{(weights[it]?:0.0)>0}.sortedByDescending{weights[it]?:0.0}
   val related=records.filter{(it.rating?:3)>=3 && it.tags.intersect(shared.toSet()).isNotEmpty()}.sortedByDescending{it.rating?:3}.take(2)
   val liked=related.filter{(it.rating?:0)>=4}
   val names=related.joinToString("、"){"《"+it.title+"》"}
   val connection=if(shared.isEmpty())"这是一部探索推荐，现有观影记录尚未提供明确的相似偏好。" else "与你记录中的"+shared.take(3).joinToString("、")+"有关"+if(names.isEmpty())"。" else "；参考了"+names+"。"
   val reason=if(liked.isEmpty())"根据已看题材尝试推荐；看过只作为弱参考，评分后会继续调整。" else "你对"+liked.joinToString("、"){"《"+it.title+"》"}+"给过较高评价，这部也包含"+shared.take(2).joinToString("、")+"元素。"
   f.tags.sumOf{weights[it]?:0.0} to MemorySuggestion(f,reason,connection)
  }.sortedWith(compareByDescending<Pair<Double,MemorySuggestion>>{it.first}.thenBy{it.second.film.id}).take(6).map{it.second}
 }
}
class WatchCoverage {
 private var source="";private var previous:Triple<Double,Double,Boolean>?=null
 private var ranges=mutableListOf<Pair<Double,Double>>()
 fun sample(source:String,position:Double,duration:Double,playing:Boolean,now:Double):Boolean {
  if(source.isEmpty() || !position.isFinite() || !duration.isFinite() || duration<60 || position<0){previous=null;return false}
  if(this.source!=source){this.source=source;previous=null;ranges.clear()}
  previous?.let{(last,time,wasPlaying)->val dt=now-time;val delta=position-last
   if(wasPlaying && playing && dt>0 && dt<=5 && delta>0 && delta<=dt*3+2) {
    ranges.add(last to position);val merged=mutableListOf<Pair<Double,Double>>()
    ranges.sortedBy{it.first}.forEach{r->val p=merged.lastOrNull();if(p!=null && r.first<=p.second+0.1)merged[merged.lastIndex]=p.first to maxOf(p.second,r.second) else merged.add(r)}
    ranges=merged
   }
  }
  previous=Triple(position,now,playing)
  val coverage=ranges.sumOf{maxOf(0.0,minOf(duration,it.second)-minOf(duration,it.first))}
  return coverage>=duration*0.7 && position>=duration-3 && position<=duration+3
 }
}
