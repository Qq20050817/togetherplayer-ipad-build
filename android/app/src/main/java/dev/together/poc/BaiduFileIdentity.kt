package dev.together.poc
import org.json.JSONObject
import java.security.MessageDigest

object BaiduFileIdentity {
 fun size(value:Any?):Long? {
  val n=when(value){is String->value.trim().toLongOrNull();is Number->value.toLong().takeIf{value.toDouble()==it.toDouble()};else->null}
  return n?.takeIf{it in 1..9007199254740991L}
 }
 fun provider(value:Any?):String? {
  val text=(value as? String)?.trim() ?: return null
  if(text=="0".repeat(32))return null
  if(Regex("^[a-fA-F0-9]{32}$").matches(text))return text.lowercase()
  if(!Regex("^[A-Za-z0-9_-]{32,128}$").matches(text))return null
  return digest(("baidu-provider-md5-v1:"+text).toByteArray(Charsets.UTF_8))
 }
 fun merge(info:JSONObject,file:BaiduFile)=file.copy(size=size(info.opt("size")) ?: size(file.size) ?: 0,fingerprint=provider(info.opt("md5")) ?: provider(file.fingerprint) ?: "")
 fun offsets(size:Long)=listOf(0L,maxOf(0L,size/2-32768),maxOf(0L,size-65536)).distinct().sorted()
 fun sample(size:Long,samples:List<Pair<Long,ByteArray>>):String {
  val bytes=java.io.ByteArrayOutputStream();bytes.write("together-baidu-sample-v1\n$size\n".toByteArray(Charsets.UTF_8))
  for((offset,data) in samples.sortedBy{it.first}) {bytes.write("\n$offset:${data.size}\n".toByteArray(Charsets.UTF_8));bytes.write(data)}
  return digest(bytes.toByteArray())
 }
 private fun digest(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).take(16).joinToString(""){"%02x".format(it.toInt() and 255)}
}
