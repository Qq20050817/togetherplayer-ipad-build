import XCTest
@testable import TogetherPoC

@MainActor final class ChatGPTAuthProbeTests:XCTestCase {
 func testBase64URLDecodeRejectsBadIdentity() {
  let data=ChatGPTIdentityVerifier.base64URL("YWJjZA")
  XCTAssertEqual(String(data:data ?? Data(),encoding:.utf8),"abcd")
  XCTAssertNil(ChatGPTIdentityVerifier.base64URL("%%not-base64"))
 }
 func testAuthorizeURLUsesOfficialHostAndExactRedirect() {
  let u=ChatGPTAuthProbe.authURL(for:[
   "client_id":"dynamic_agent_client",
   "redirect_uri":"http://127.0.0.1:1455/auth/callback",
   "scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
   "code_challenge_method":"S256"
  ])
  XCTAssertEqual(u?.scheme,"https")
  XCTAssertEqual(u?.host,"auth.openai.com")
  XCTAssertEqual(u?.path,"/api/accounts/authorize")
  let q=URLComponents(url:u!,resolvingAgainstBaseURL:false)?.queryItems
  XCTAssertTrue(q?.contains(where:{$0.name=="redirect_uri" && $0.value=="http://127.0.0.1:1455/auth/callback"}) == true)
  XCTAssertTrue(q?.contains(where:{$0.name=="scope" && $0.value?.contains("chatgpt.tokens.use.direct")==true}) == true)
 }
}