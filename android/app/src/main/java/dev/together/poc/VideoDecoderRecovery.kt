package dev.together.poc

/** Runtime recovery is bounded per source; never repeat the failing decoder. */
class VideoDecoderRecovery {
 private var source = ""
 private val excluded = linkedSetOf<String>()
 private var attempts = 0
 fun beginSource(uri:String) {
  if(source != uri) {source=uri;excluded.clear();attempts=0}
 }
 fun allowed(name:String) = name !in excluded
 fun recover(mime:String?,failed:String?,alternatives:List<String>):String? {
  if(mime != "video/hevc" || failed.isNullOrBlank() || attempts >= 2 || failed in excluded)return null
  val next=alternatives.firstOrNull {it != failed && allowed(it)} ?: return null
  excluded.add(failed);attempts++
  return next
 }
}
