package dev.together.poc

/** Bounded audio decoder fallback. Keep the same language and only select playable tracks. */
internal object AudioTrackFallback {
 data class Option(val mime:String?,val language:String?,val supported:Boolean)
 private val failing=setOf("audio/vnd.dts","audio/vnd.dts.hd","audio/true-hd")
 private val compatible=setOf("audio/ac3","audio/eac3","audio/mp4a-latm")
 fun select(failedMime:String?,failedLanguage:String?,tracks:List<Option>):Int? {
  if(failedMime !in failing)return null
  val lang=failedLanguage?.trim()?.lowercase()?.takeIf{it.isNotEmpty() && it!="und"} ?: return null
  return tracks.indexOfFirst{it.supported && it.mime in compatible && it.language?.lowercase()==lang}
   .takeIf{it>=0}
 }
}
