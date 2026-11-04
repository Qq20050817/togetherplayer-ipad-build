package dev.together.poc
import java.net.URI

/** Network fallback is explicit and never drops account-specific HTTP headers. */
internal object CompatibilitySourcePolicy {
 fun allows(value:String,allowHttp:Boolean):Boolean {
  val uri=runCatching {URI(value)}.getOrNull() ?: return false
  return when(uri.scheme?.lowercase()) {
   "content","file"->true
   "http","https"->{
    val host=uri.host?.lowercase() ?: return false
    allowHttp && uri.userInfo==null && host!="baidu.com" && !host.endsWith(".baidu.com") && host!="baidupcs.com" && !host.endsWith(".baidupcs.com")
   }
   else->false
  }
 }
}
