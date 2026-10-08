package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject
class BaiduIdentityTest {
 @Test fun invalidDetailKeepsValidListFields() {
  val file=BaiduFile(1,"movie.mkv","/movie.mkv",6800248966,false,"a".repeat(32))
  val merged=BaiduFileIdentity.merge(JSONObject().put("size",0).put("md5",""),file)
  assertEquals(file.size,merged.size);assertEquals(file.fingerprint,merged.fingerprint)
  assertEquals(file.size,BaiduFileIdentity.size("6800248966"));assertNull(BaiduFileIdentity.size(-1));assertNull(BaiduFileIdentity.size(1.5))
  assertNotNull(BaiduFileIdentity.provider("g".repeat(32)))
 }
 @Test fun crossPlatformSampleIdentityChecksActualBytes() {
  val samples=listOf(0L to "hello".toByteArray())
  assertEquals("f08c3fe9dd10774cc643aff6d17165ab",BaiduFileIdentity.sample(5,samples))
  assertNotEquals(BaiduFileIdentity.sample(5,samples),BaiduFileIdentity.sample(5,listOf(0L to "world".toByteArray())))
  assertEquals(listOf(0L),BaiduFileIdentity.offsets(5));assertEquals(listOf(0L,67232L,134464L),BaiduFileIdentity.offsets(200000))
 }
}
