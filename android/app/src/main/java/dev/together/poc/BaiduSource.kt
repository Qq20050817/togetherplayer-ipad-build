package dev.together.poc
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import org.json.JSONArray
import java.net.URI
import java.net.URLDecoder

// Authorization is memory-only; this adapter never talks to Together Backend.
data class BaiduFile(val id:Long,val name:String,val path:String,val size:Long,val directory:Boolean,val fingerprint:String)
class BaiduSourceAdapter {
 companion object {
  const val AUTHORIZE="https://openapi.baidu.com/oauth/2.0/authorize?client_id=QHOuRXiepJBMjtk0esLhrPoNlQyYd0mF&redirect_uri=oob&response_type=token&scope=basic%2Cnetdisk"
  fun parseAuthorization(raw:String):String {
   val text=raw.trim()
   val value=if(text.startsWith("https://")) {
    val u=URI(text);require(u.host=="openapi.baidu.com" && u.userInfo==null)
    (u.rawFragment ?: "").split('&').map {it.split('=',limit=2)}.firstOrNull {it.size==2 && it[0]=="access_token"}?.get(1)?.let {URLDecoder.decode(it,"UTF-8")} ?: throw IllegalArgumentException()
   }else text
   require(value.length in 1..4096 && Regex("^[A-Za-z0-9._~-]+$").matches(value));return value
  }
  fun allowedURL(value:String):Boolean=runCatching {val u=URI(value);val h=u.host?.lowercase() ?: return false;u.scheme=="https" && u.userInfo==null && listOf("baidu.com","baidupcs.com","bcebos.com").any {h==it || h.endsWith(".$it")}}.getOrDefault(false)
 }
 // API redirects cannot carry account tokens to unrelated hosts.
 private val client=OkHttpClient.Builder().followRedirects(false).callTimeout(20,java.util.concurrent.TimeUnit.SECONDS).build()
 @Volatile private var token=""
 fun authorized()=token.isNotEmpty()
 fun authorize(raw:String){token=parseAuthorization(raw)}
 fun clear(){token=""}
 fun close(){clear();client.dispatcher.executorService.shutdown()}
 private fun read(path:String,query:Map<String,String>):JSONObject {
  require(authorized());val u=HttpUrl.Builder().scheme("https").host("pan.baidu.com").encodedPath(path).addQueryParameter("access_token",token)
  query.forEach {(k,v)->u.addQueryParameter(k,v)}
  return client.newCall(Request.Builder().url(u.build()).header("User-Agent","pan.baidu.com").build()).execute().use {r->
   require(r.isSuccessful);val body=r.body ?: throw IllegalStateException();val source=body.source();source.request(2_000_001L);require(source.buffer.size<=2_000_000);val bytes=source.buffer.readByteArray()
   val value=JSONObject(String(bytes,Charsets.UTF_8));require(value.optInt("errno",value.optInt("error_code",0))==0);value
  }
 }
 fun list(directory:String,page:Int):List<BaiduFile> {
  require(directory.startsWith('/') && page in 0..10000)
  val list=read("/rest/2.0/xpan/file",mapOf("method" to "list","dir" to directory,"start" to (page*100).toString(),"limit" to "100","order" to "name","desc" to "0")).getJSONArray("list")
  return (0 until list.length()).map {i->val f=list.getJSONObject(i);BaiduFile(f.getLong("fs_id"),f.optString("server_filename",f.getString("path")),f.getString("path"),BaiduFileIdentity.size(f.opt("size")) ?: 0,f.optInt("isdir")==1,BaiduFileIdentity.provider(f.opt("md5")) ?: "")}
 }
 private fun range(source:String,offset:Long,count:Int):Pair<Long,ByteArray> {
  var url=source
  repeat(6) {
   require(allowedURL(url))
   client.newCall(Request.Builder().url(url).header("User-Agent","pan.baidu.com").header("Range","bytes=$offset-${offset+count-1}").build()).execute().use {r->
    if(r.code in listOf(301,302,303,307,308)) {url=r.request.url.resolve(r.header("Location") ?: error("Missing redirect"))?.toString() ?: error("Invalid redirect")}
    else {
     require(r.code==206){"Source does not support bounded Range"}
     val m=Regex("^bytes ([0-9]+)-([0-9]+)/([0-9]+)$").matchEntire(r.header("Content-Range") ?: "") ?: error("Invalid Content-Range")
     val start=m.groupValues[1].toLong();val end=m.groupValues[2].toLong();val total=m.groupValues[3].toLong()
     require(total in 1..9007199254740991L && start==offset && end==minOf(offset+count-1,total-1))
     val expected=end-start+1;require(expected in 1..65536)
     val body=r.body ?: error("No range body");val data=body.source();data.request(expected+1);require(data.buffer.size==expected)
     return total to data.buffer.readByteArray()
    }
   }
  }
  error("Too many redirects")
 }
 fun playable(file:BaiduFile):Pair<BaiduFile,String> {
  require(!file.directory)
  val f=read("/rest/2.0/xpan/multimedia",mapOf("method" to "filemetas","dlink" to "1","fsids" to JSONArray().put(file.id).toString())).getJSONArray("list").getJSONObject(0)
  require(f.getLong("fs_id")==file.id)
  val raw=f.getString("dlink");require(allowedURL(raw))
  val u=raw.toHttpUrl().newBuilder().removeAllQueryParameters("access_token").addQueryParameter("access_token",token).build().toString()
  var selected=BaiduFileIdentity.merge(f,file)
  // Both accounts use the same byte-derived identity, independent of API MD5 format.
  run {
   val first=range(u,0,65536);val samples=mutableListOf(0L to first.second)
   for(offset in BaiduFileIdentity.offsets(first.first).drop(1)) {
    val part=range(u,offset,minOf(65536L,first.first-offset).toInt());require(part.first==first.first)
    samples.add(offset to part.second)
   }
   selected=selected.copy(size=first.first,fingerprint=BaiduFileIdentity.sample(first.first,samples))
  }
  return selected to u
 }
}
