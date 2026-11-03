package dev.together.poc
import okhttp3.mockwebserver.*
import okio.Buffer
internal class FixtureHttpServer(private val bytes:ByteArray):java.io.Closeable {
 val server=MockWebServer()
 init {
  server.dispatcher=object:Dispatcher(){override fun dispatch(request:RecordedRequest):MockResponse {
   if(request.method=="HEAD")return MockResponse().setHeader("Content-Length",bytes.size).setHeader("Content-Type","video/mp4")
   val range=request.getHeader("Range")
   if(range==null)return MockResponse().setHeader("Content-Type","video/mp4").setBody(Buffer().write(bytes))
   val parts=range.removePrefix("bytes=").split('-');val start=parts[0].toIntOrNull() ?: 0
   val end=(parts.getOrNull(1)?.toIntOrNull() ?: bytes.lastIndex).coerceAtMost(bytes.lastIndex)
   if(start>bytes.lastIndex || start>end)return MockResponse().setResponseCode(416).setHeader("Content-Range","bytes */${bytes.size}")
   return MockResponse().setResponseCode(206).setHeader("Content-Type","video/mp4").setHeader("Content-Range","bytes $start-$end/${bytes.size}").setBody(Buffer().write(bytes.copyOfRange(start,end+1)))
  }}
  server.start()
 }
 val url get()=server.url("/fixture.mp4").toString()
 override fun close(){server.shutdown()}
}
