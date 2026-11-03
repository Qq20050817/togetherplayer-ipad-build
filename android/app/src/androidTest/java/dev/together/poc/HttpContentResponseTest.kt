package dev.together.poc
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.MockResponse
import org.junit.Test
import org.junit.Assert.*
class HttpContentResponseTest {
 @Test fun errorPageIsDiagnosedBeforeExtractorWithoutRetry(){
  MockWebServer().use{s->s.enqueue(MockResponse().setHeader("Content-Type","text/html; charset=utf-8").setBody("<html>unavailable</html>"));s.start()
   val data=HttpMediaDataSource.factory().createDataSource()
   try{data.open(DataSpec(android.net.Uri.parse(s.url("/movie.mkv").toString())));fail("HTML error page accepted as video")}
   catch(e:HttpDataSource.InvalidContentTypeException){val diagnosis=HttpFailureDiagnosis.classify(e.reason,null);assertEquals("UNEXPECTED_CONTENT",diagnosis.category);assertFalse(diagnosis.retryable)}
   finally{data.close()}
   assertEquals(1,s.requestCount)
  }
 }
 @Test fun unknownAndGenericBinaryMimeStillReadRawBytes(){
  MockWebServer().use{s->s.enqueue(MockResponse().setBody("bytes"));s.enqueue(MockResponse().setHeader("Content-Type","application/octet-stream").setBody("bytes"));s.start()
   repeat(2){val data=HttpMediaDataSource.factory().createDataSource();try{assertEquals(5L,data.open(DataSpec(android.net.Uri.parse(s.url("/movie.mkv").toString()))));val b=ByteArray(5);assertEquals(5,data.read(b,0,5));assertEquals("bytes",String(b))}finally{data.close()}}
  }
 }
}
