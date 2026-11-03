package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject
class PlaybackDiagnosticJournalTest {
 @Test fun recordsCodesButDropsCredentialsUrlsPathsAndUnexpectedFields(){
  val input=JSONObject().put("token","secret").put("sourceKind","HTTP网络").put("details",JSONObject().put("httpStatus",503).put("category","HTTP_SERVER").put("codecName","https://example.org/private?sig=secret").put("file","private movie").put("mimeType","video/hevc"))
  val safe=PlaybackDiagnosticJournal.sanitize(input).toString()
  assertTrue(safe.contains("HTTP_SERVER"));assertTrue(safe.contains("video/hevc"));assertFalse(safe.contains("secret"));assertFalse(safe.contains("private"));assertFalse(safe.contains("token"))
 }
}
