package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
class BaiduSourceTest {
 @Test fun descriptorMatchesTransferredContentAndInvalidatesNewSelection(){
  val one=BaiduMediaReference.create("A".repeat(32),6800248966L)!!
  val two=BaiduMediaReference.create("a".repeat(32),6800248966L)!!
  assertNotEquals(one.value,two.value);assertEquals(one,BaiduMediaReference.parse(one.value))
  assertTrue(one.matches("A".repeat(32),6800248966L));assertFalse(one.matches("b".repeat(32),6800248966L));assertFalse(one.matches("a".repeat(32),5L))
  assertNull(BaiduMediaReference.parse(one.value+"?access_token=secret"));assertNull(BaiduMediaReference.create("a".repeat(32),9007199254740992L));assertNull(BaiduMediaReference.create("",5L))
 }
 @Test fun authorizationAndAllowedDomainsDoNotAcceptPasswordOrOtherHosts(){
  assertEquals("mock-test-token",BaiduSourceAdapter.parseAuthorization("https://openapi.baidu.com/oauth/2.0/login_success#expires_in=100&access_token=mock-test-token"))
  for(value in listOf("https://evil.example/#access_token=secret","Cookie: BDUSS=secret","https://openapi.baidu.com/oauth/2.0/login_success#expires_in=100")) {try{BaiduSourceAdapter.parseAuthorization(value);fail("invalid authorization accepted")}catch(e:IllegalArgumentException){}}
  assertTrue(BaiduSourceAdapter.allowedURL("https://d.pcs.baidu.com/file"));assertFalse(BaiduSourceAdapter.allowedURL("https://baidu.com.evil.example/file"));assertFalse(BaiduSourceAdapter.allowedURL("http://pan.baidu.com/file"));assertFalse(BaiduSourceAdapter.allowedURL("https://user:secret@pan.baidu.com/file"))
 }
}
