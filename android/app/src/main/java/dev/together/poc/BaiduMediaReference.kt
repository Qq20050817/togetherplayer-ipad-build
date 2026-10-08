package dev.together.poc
import java.util.UUID

data class BaiduMediaReference(val nonce:String,val fingerprint:String,val size:Long) {
 val value get()="baidu://$nonce/$fingerprint/$size"
 fun matches(fingerprint:String,size:Long)=this.fingerprint==fingerprint.lowercase() && this.size==size
 companion object {
  fun parse(value:String):BaiduMediaReference? {
   if(!Regex("^baidu://[a-f0-9]{32}/[a-f0-9]{32}/[1-9][0-9]{0,15}$").matches(value))return null
   val p=value.removePrefix("baidu://").split('/');val size=p[2].toLongOrNull() ?: return null
   if(size>9007199254740991L)return null
   return BaiduMediaReference(p[0],p[1],size)
  }
  fun create(fingerprint:String,size:Long)=parse("baidu://${UUID.randomUUID().toString().replace("-","")}/${fingerprint.lowercase()}/$size")
 }
}
