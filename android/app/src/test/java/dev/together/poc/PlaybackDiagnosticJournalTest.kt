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
 @Test fun preservesOnlySafeHdrSelectionEvidence() {
  val input=JSONObject().put("details",JSONObject()
   .put("hdrHardwareSurfaceRequested",true)
   .put("boundedHardwareTrial",true)
   .put("colorTransfer",6)
   .put("colorSpace",6)
   .put("mediaUrl","https://secret.example/private?sig=token")
   .put("candidates",org.json.JSONArray().put("private codec details")))
  val safe=PlaybackDiagnosticJournal.sanitize(input)
  val details=safe.getJSONObject("details")
  assertTrue(details.getBoolean("hdrHardwareSurfaceRequested"))
  assertTrue(details.getBoolean("boundedHardwareTrial"))
  assertEquals(6,details.getInt("colorTransfer"))
  assertEquals(6,details.getInt("colorSpace"))
  assertFalse(details.has("mediaUrl"))
  assertFalse(details.has("candidates"))
 }
}
