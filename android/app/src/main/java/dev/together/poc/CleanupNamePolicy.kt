package dev.together.poc

object CleanupNamePolicy {
 val subtitleExtensions=setOf("srt","vtt","ass","ssa","sup","sub","idx","smi","ttml","dfxp")
 private val tags=setOf("zh","zh-cn","zh-tw","zh-hk","zh-hans","zh-hant","chs","cht","chi","zho","cn","hans","hant","简体","繁体","简体中文","繁体中文","中文","中英","双语","eng","en","english","ja","jpn","jp","ko","kor","fr","fra","fre","de","deu","ger","es","spa","pt","por","ru","rus","it","ita","ar","ara","th","tha","vi","vie","id","ind","forced","sdh","cc","default","full","utf8","utf-8")
 fun isSubtitle(name:String)=name.substringAfterLast('.',"").lowercase(java.util.Locale.ROOT) in subtitleExtensions
 fun associatedSubtitle(name:String,movie:String):Boolean {
  if(!isSubtitle(name))return false
  val base=movie.substringBeforeLast('.',movie).lowercase(java.util.Locale.ROOT)
  val stem=name.substringBeforeLast('.',name).lowercase(java.util.Locale.ROOT)
  if(stem==base)return true
  if(!stem.startsWith("$base."))return false
  val parts=stem.substring(base.length+1).split(Regex("[.&+ _]+")).filter{it.isNotEmpty()}
  return parts.isNotEmpty() && parts.all{it in tags}
 }
}
