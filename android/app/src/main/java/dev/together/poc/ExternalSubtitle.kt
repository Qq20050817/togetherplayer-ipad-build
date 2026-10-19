package dev.together.poc

/** Local text subtitles only. ASS positioning, drawings and fonts are not rendered. */
data class SubtitleCue(val start: Long,val end: Long,val text: String)
class ExternalSubtitle(cues: List<SubtitleCue>) {
 // Build once on import. Playback never scans the full subtitle file.
 val cues: List<SubtitleCue> = cues.toList()
 private val ordered = this.cues.indices.sortedBy {this.cues[it].start}
 private val maximumEnds = LongArray(ordered.size).also {ends->
  var maximum=Long.MIN_VALUE
  ordered.forEachIndexed {index,original->maximum=maxOf(maximum,this.cues[original].end);ends[index]=maximum}
 }
 fun textAt(position: Long,delay: Long=0): String {
  val time=position-delay
  var low=0;var high=ordered.size
  while(low<high){val mid=(low+high) ushr 1;if(cues[ordered[mid]].start<=time)low=mid+1 else high=mid}
  var index=low-1
  val active=ArrayList<Int>()
  while(index>=0 && maximumEnds[index]>time){val original=ordered[index];val cue=cues[original];if(time>=cue.start && time<cue.end)active.add(original);index--}
  // Preserve source ordering for overlapping ASS lines and unsorted inputs.
  active.sort()
  return active.joinToString("\n"){cues[it].text}
 }
 companion object {
  const val MAX_BYTES=5*1024*1024
  private fun time(value: String): Long? {
   val m=Regex("^(?:(\\d+):)?(\\d{1,2}):(\\d{1,2})(?:[.,](\\d{1,3}))?$").matchEntire(value.trim()) ?: return null
   val h=m.groupValues[1].toLongOrNull() ?: 0;val min=m.groupValues[2].toLong();val sec=m.groupValues[3].toLong()
   if(min>=60 || sec>=60 || h>1000)return null
   return (h*3600+min*60+sec)*1000+(m.groupValues[4].padEnd(3,'0').toLongOrNull() ?: 0)
  }
  /** Let viewers override old Chinese/Korean subtitle encodings without saving a converted copy. */
  val TEXT_ENCODINGS = listOf("UTF-8", "GB18030", "Big5", "EUC-KR", "UTF-16LE", "UTF-16BE", "windows-1252")

  private fun textEncoding(bytes: ByteArray, forcedCharset: String?): String {
   if (forcedCharset != null) {
    require(forcedCharset in TEXT_ENCODINGS) {"不支持的字幕编码"}
    return bytes.toString(charset(forcedCharset))
   }
   if (bytes.size >= 2) {
    val first = bytes[0].toInt() and 255
    val second = bytes[1].toInt() and 255
    if (first == 255 && second == 254) return bytes.toString(Charsets.UTF_16LE)
    if (first == 254 && second == 255) return bytes.toString(Charsets.UTF_16BE)
   }
   // UTF-16 subtitle files occasionally omit the BOM. Check zero-byte parity.
   val sampled = minOf(bytes.size, 256)
   if (sampled >= 24) {
    var evenZeros = 0
    var oddZeros = 0
    for (i in 0 until sampled) {
     if (bytes[i].toInt() == 0) {
      if (i % 2 == 0) evenZeros++ else oddZeros++
     }
    }
    if (oddZeros >= sampled / 5 && evenZeros <= sampled / 32) return bytes.toString(Charsets.UTF_16LE)
    if (evenZeros >= sampled / 5 && oddZeros <= sampled / 32) return bytes.toString(Charsets.UTF_16BE)
   }
   val utf8 = runCatching {
    Charsets.UTF_8.newDecoder()
     .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
     .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
     .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
   }.getOrNull()
   return utf8 ?: bytes.toString(charset("GB18030"))
  }

  fun parse(bytes: ByteArray, forcedCharset: String? = null): ExternalSubtitle {
   require(bytes.size <= MAX_BYTES) {"字幕超过5MB"}
   val text = textEncoding(bytes, forcedCharset).removePrefix("\uFEFF")
    .replace("\r\n","\n").replace('\r','\n')
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
