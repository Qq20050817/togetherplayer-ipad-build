package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class HttpContentTypeTest {
 @Test fun structuredErrorsRejectedAndMediaMimeVariationsPreserved(){
  for(mime in listOf("text/html; charset=UTF-8","application/JSON","application/problem+json","application/xhtml+xml"))assertFalse(HttpMediaDataSource.acceptsContentType(mime))
  for(mime in listOf(null,"","application/octet-stream","video/x-matroska","video/mp4","application/vnd.apple.mpegurl","text/vtt","text/plain"))assertTrue(HttpMediaDataSource.acceptsContentType(mime))
 }
}
