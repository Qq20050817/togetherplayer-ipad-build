package dev.together.poc

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** At most three 64KiB identity samples. Never uploads media or logs a URL. */
internal class HttpRangeIdentity(client:OkHttpClient) {
 enum class Result { MATCH, DIFFERENT, UNAVAILABLE }
 private val client=client.newBuilder().callTimeout(10,TimeUnit.SECONDS).readTimeout(5,TimeUnit.SECONDS).build()
 private val cancelled=AtomicBoolean(false)
 private val active=AtomicReference<Call?>()
 fun cancel(){cancelled.set(true);active.getAndSet(null)?.cancel()}
 private fun call(request:Request):okhttp3.Response {
  if(cancelled.get())throw IOException("identity_cancelled")
  val call=client.newCall(request);active.set(call)
  if(cancelled.get()){call.cancel();throw IOException("identity_cancelled")}
  return call.execute()
 }
 fun verify(url:String,localSize:Long,fingerprint:String):Result { return try {
  val size=call(Request.Builder().url(url).header("Accept-Encoding","identity").head().build()).use {r->
   if(r.code!=200 || r.header("Content-Type").orEmpty().contains("text/html",true))null
   else r.header("Content-Length")?.toLongOrNull()?.takeIf{it in 1..9007199254740991L}
  } ?: return Result.UNAVAILABLE
  if(size!=localSize)return Result.DIFFERENT
  val samples=ArrayList<Pair<Long,ByteArray>>()
  for(offset in BaiduFileIdentity.offsets(size)){
   val count=minOf(65536L,size-offset).toInt()
   val request=Request.Builder().url(url).header("Accept-Encoding","identity").header("Range","bytes=$offset-${offset+count-1}").build()
   call(request).use {r->
    val range=parseContentRange(r.header("Content-Range"))
    val body=r.body ?: throw IOException("identity_no_body")
    if(r.code!=206 || range!=Triple(offset,offset+count-1,size) || (body.contentLength()>=0 && body.contentLength()!=count.toLong()))throw IOException("identity_range_invalid")
    val bytes=ByteArray(count)
    body.byteStream().use {input->var read=0;while(read<count){val n=input.read(bytes,read,count-read);if(n<0)throw IOException("identity_incomplete");read+=n};if(input.read()!=-1)throw IOException("identity_extra_body")}
    samples.add(offset to bytes)
   }
  }
  if(cancelled.get())Result.UNAVAILABLE else if(BaiduFileIdentity.sample(size,samples)==fingerprint)Result.MATCH else Result.DIFFERENT
 } catch(_:Exception){Result.UNAVAILABLE} finally {active.set(null)}
 }
 companion object {
  fun parseContentRange(value:String?):Triple<Long,Long,Long>? {
   val m=Regex("bytes ([0-9]+)-([0-9]+)/([0-9]+)").matchEntire(value?.trim() ?: "") ?: return null
   val start=m.groupValues[1].toLongOrNull() ?: return null
   val end=m.groupValues[2].toLongOrNull() ?: return null
   val total=m.groupValues[3].toLongOrNull() ?: return null
   if(total !in 1..9007199254740991L || start<0 || end<start || end>=total)return null
   return Triple(start,end,total)
  }
 }
}
