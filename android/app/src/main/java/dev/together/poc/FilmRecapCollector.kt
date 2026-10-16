package dev.together.poc

// Wire-compatible with the host's existing idempotent CHAT_MESSAGE protocol.
// Each section stays private to the drawer; chat does not render fragments.
class FilmRecapCollector {
 data class Completed(val id:String,val text:String)
 private var currentId=""
 private var expected=0
 private val parts=mutableMapOf<Int,String>()
 var latest:Completed?=null
  private set

 fun clear() {
  currentId="";expected=0;parts.clear();latest=null
 }
 fun consume(clientId:String,text:String):Completed? {
  val id=Regex("^bank-final:([a-f0-9]{32}):(\\d{1,3})$").matchEntire(clientId) ?:return null
  val index=id.groupValues[2].toIntOrNull() ?:return null
  val line=Regex("^🎬 片尾结算（(\\d{1,3})/(\\d{1,3})）\\n").find(text) ?:return null
  val oneBased=line.groupValues[1].toIntOrNull() ?:return null
  val total=line.groupValues[2].toIntOrNull() ?:return null
  if(total !in 1..100 || index !in 0 until total || oneBased!=index+1 || text.length>950)return null
  val reportId=id.groupValues[1]
  if(latest?.id==reportId)return null
  if(currentId!=reportId || expected!=total) {
   currentId=reportId;expected=total;parts.clear()
  }
  parts.putIfAbsent(index,text.substring(line.value.length))
  if(parts.size!=total)return null
  val full=(0 until total).joinToString("") {parts[it].orEmpty()}
  if(full.isBlank() || full.length>70000)return null
  return Completed(reportId,full).also {latest=it;parts.clear()}
 }
}
