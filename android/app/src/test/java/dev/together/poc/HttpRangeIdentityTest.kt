package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okio.Buffer
class HttpRangeIdentityTest {
 @Test fun parsesOffsetsBeyondFourGiBWithoutIntegerTruncation(){assertEquals(Triple(4294967296L,4295032831L,9000000000L),HttpRangeIdentity.parseContentRange("bytes 4294967296-4295032831/9000000000"));assertNull(HttpRangeIdentity.parseContentRange("bytes 0-5/5"));assertNull(HttpRangeIdentity.parseContentRange("bytes 0-1/999999999999999999999999"))}
 @Test fun validatesHugeResourceUsingOnlyThreeBoundedSamples(){
  val size=9000000000L
  fun bytes(offset:Long,count:Int)=ByteArray(count){((offset+it)%251).toByte()}
  val samples=BaiduFileIdentity.offsets(size).map{it to bytes(it,65536)}
  val expected=BaiduFileIdentity.sample(size,samples)
  val server=MockWebServer()
  server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
   if(request.method=="HEAD")return MockResponse().setHeader("Content-Length",size).setHeader("Content-Type","video/x-matroska")
   val range=request.getHeader("Range")!!.removePrefix("bytes=").split('-');val start=range[0].toLong();val end=range[1].toLong()
   return MockResponse().setResponseCode(206).setHeader("Content-Range","bytes $start-$end/$size").setBody(Buffer().write(bytes(start,(end-start+1).toInt())))
  }}
  server.start()
  try {assertEquals(HttpRangeIdentity.Result.MATCH,HttpRangeIdentity(OkHttpClient()).verify(server.url("/movie.mkv").toString(),size,expected));assertEquals(4,server.requestCount)}finally{server.shutdown()}
 }
 @Test fun refusesIgnoredRangeAndNeverReadsWholeResponse(){
  val server=MockWebServer();server.enqueue(MockResponse().setHeader("Content-Length",1000));server.enqueue(MockResponse().setBody("wrong full response"));server.start()
  try{assertEquals(HttpRangeIdentity.Result.UNAVAILABLE,HttpRangeIdentity(OkHttpClient()).verify(server.url("/movie.mp4").toString(),1000,"a".repeat(32)));assertEquals(2,server.requestCount)}finally{server.shutdown()}
 }
}
