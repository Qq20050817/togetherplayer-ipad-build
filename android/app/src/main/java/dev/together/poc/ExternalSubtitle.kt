package dev.together.poc

/** Local text subtitles only. ASS positioning, drawings and fonts are not rendered. */
data class SubtitleCue(val start: Long,val end: Long,val text: String)
class ExternalSubtitle(val cues: List<SubtitleCue>) {
 fun textAt(position: Long,delay: Long=0)=cues.filter {position-delay>=it.start && position-delay<it.end}.joinToString("\n"){it.text}
 companion object {
  const val MAX_BYTES=5*1024*1024
  private fun time(value: String): Long? {
   val m=Regex("^(?:(\\d+):)?(\\d{1,2}):(\\d{1,2})(?:[.,](\\d{1,3}))?$").matchEntire(value.trim()) ?: return null
   val h=m.groupValues[1].toLongOrNull() ?: 0;val min=m.groupValues[2].toLong();val sec=m.groupValues[3].toLong()
   if(min>=60 || sec>=60 || h>1000)return null
   return (h*3600+min*60+sec)*1000+(m.groupValues[4].padEnd(3,'0').toLongOrNull() ?: 0)
  }
  fun parse(bytes: ByteArray): ExternalSubtitle {
   require(bytes.size<=MAX_BYTES){"字幕超过5MB"}
   val text=when {
    bytes.size>=2 && (bytes[0].toInt() and 255)==255 && (bytes[1].toInt() and 255)==254 -> bytes.toString(Charsets.UTF_16LE)
    bytes.size>=2 && (bytes[0].toInt() and 255)==254 && (bytes[1].toInt() and 255)==255 -> bytes.toString(Charsets.UTF_16BE)
    else -> {val utf=bytes.toString(Charsets.UTF_8);if('\uFFFD' in utf)bytes.toString(charset("GB18030")) else utf}
   }.removePrefix("\uFEFF").replace("\r\n","\n").replace('\r','\n')
   val cues=ArrayList<SubtitleCue>()
   if(text.contains("[Events]",true)) {
    var fields=listOf("Layer","Start","End","Style","Name","MarginL","MarginR","MarginV","Effect","Text")
    var events=false
    for(line in text.lines()) {
     if(line.trim().startsWith("[")){events=line.trim().equals("[Events]",true);continue};if(!events)continue
     if(line.startsWith("Format:",true)){fields=line.substringAfter(':').split(',').map {it.trim()};continue}
     if(!line.startsWith("Dialogue:",true))continue
     val parts=line.substringAfter(':').trimStart().split(',',limit=fields.size)
     fun part(name: String)=fields.indexOfFirst {it.equals(name,true)}.let {parts.getOrNull(it)}
     val a=part("Start")?.let {time(it)} ?: continue;val b=part("End")?.let {time(it)} ?: continue
     val raw=part("Text") ?: continue;if(Regex("\\\\p[1-9]").containsMatchIn(raw))continue
     val clean=raw.replace(Regex("\\{[^}]*}"),"").replace("\\N","\n").replace("\\n","\n").replace("\\h"," ")
     if(b>a && clean.isNotBlank())cues.add(SubtitleCue(a,b,clean))
    }
   } else for(block in text.split(Regex("\n\\s*\n"))) {
    val lines=block.lines();if(lines.firstOrNull()?.trim()?.let {it.startsWith("NOTE") || it=="STYLE" || it=="REGION"}==true)continue
    val i=lines.indexOfFirst {"-->" in it};if(i<0)continue
    val times=lines[i].split("-->");val a=time(times[0]) ?: continue;val b=time(times.getOrNull(1)?.trim()?.substringBefore(' ') ?: "") ?: continue
    val clean=lines.drop(i+1).joinToString("\n").replace(Regex("<[^>]*>"),"").replace("&amp;","&").replace("&lt;","<").replace("&gt;",">")
    if(b>a && clean.isNotBlank())cues.add(SubtitleCue(a,b,clean))
   }
   require(cues.isNotEmpty()){"没有可读取的字幕（支持SRT、VTT、ASS/SSA文本）"}
   return ExternalSubtitle(cues.sortedBy {it.start})
  }
 }
}
