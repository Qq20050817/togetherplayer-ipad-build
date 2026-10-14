import XCTest
@testable import TogetherPoC

final class ChatGPTRequestSupportTests:XCTestCase {
 func testTimeoutReportsCorrectStageAndHost() {
  for stage in [ChatGPTRequestStage.authorization,.models,.response,.stream] {
   let error=ChatGPTRequestFailure.network(URLError(.timedOut),stage:stage)
   XCTAssertTrue(error.localizedDescription.contains(stage.title))
   XCTAssertTrue(error.localizedDescription.contains(stage.host))
   XCTAssertTrue(error.localizedDescription.contains("超时"))
  }
 }
 func testCountryRestrictionHasExplicitDiagnosticWithoutCredentialInvalidation() {
  let error=ChatGPTRequestFailure(stage:.authorization,httpCode:403,serviceCode:"unsupported_country_region_territory")
  XCTAssertTrue(error.localizedDescription.contains("国家或地区"))
  XCTAssertFalse(ChatGPTRequestFailure.unusableRefresh(error.serviceCode))
 }
 func testCancellationIsNeverReportedAsNetworkFailure() {
  XCTAssertTrue(ChatGPTRequestFailure.network(URLError(.cancelled),stage:.stream) is CancellationError)
  XCTAssertTrue(ChatGPTRequestFailure.network(CancellationError(),stage:.models) is CancellationError)
 }
 func testModelCacheExpiresAndCannotCrossAccounts() {
  var cache=ChatGPTModelCache();let model=ChatGPTAvailableModel(id:"plan-model",name:"订阅模型")
  cache.store(model,account:"account-a",now:10)
  XCTAssertEqual(cache.value(account:"account-a",now:309),model)
  XCTAssertNil(cache.value(account:"account-a",now:310))
  XCTAssertNil(cache.value(account:"account-b",now:11))
  cache.clear();XCTAssertNil(cache.value(account:"account-a",now:11))
 }
 func testPlanCatalogPreservesVisibleServerOrderingWithoutPaidAPIFallback() {
  let body:[String:Any] = ["models":[["slug":"hidden","visibility":"hidden"],["slug":"first","visibility":"list","display_name":"第一项"],["slug":"second","visibility":"list"]]]
  XCTAssertEqual(ChatGPTModelCache.select(body),ChatGPTAvailableModel(id:"first",name:"第一项"))
  XCTAssertNil(ChatGPTModelCache.select(["data":[["id":"api-key-model"]]]))
 }
 func testExplicitModelSelectionNeverSilentlyFallsBack() {
  let catalog=[ChatGPTAvailableModel(id:"default",name:"默认"),ChatGPTAvailableModel(id:"deep",name:"深度")]
  XCTAssertEqual(ChatGPTModelCache.resolve(catalog,preferred:"deep")?.id,"deep")
  XCTAssertEqual(ChatGPTModelCache.resolve(catalog,preferred:"")?.id,"default")
  XCTAssertNil(ChatGPTModelCache.resolve(catalog,preferred:"removed"))
  XCTAssertTrue(ChatGPTRequestFailure(stage:.models,serviceCode:"selected_model_not_available").localizedDescription.contains("指定模型"))
 }
 func testCatalogFiltersHiddenAndDuplicateModelsWhileCachingEntireList() {
  let body:[String:Any] = ["models":[["slug":"hidden","visibility":"hidden"],["slug":"first","visibility":"list"],["slug":"second","visibility":"list"],["slug":"first","visibility":"list"]]]
  let catalog=ChatGPTModelCache.parse(body)
  XCTAssertEqual(catalog.map(\.id),["first","second"])
  var cache=ChatGPTModelCache();cache.store(catalog,account:"a",now:10)
  XCTAssertEqual(cache.catalog(account:"a",now:11),catalog)
  XCTAssertNil(cache.catalog(account:"b",now:11))
 }
 func testOnlyTerminalRefreshCodesRequireCredentialRemoval() {
  for code in ["invalid_grant","refresh_token_expired","refresh_token_reused"] {XCTAssertTrue(ChatGPTRequestFailure.unusableRefresh(code))}
  for code in ["invalid_client","subscription_sharing_usage_unavailable","insufficient_scopes"] {XCTAssertFalse(ChatGPTRequestFailure.unusableRefresh(code))}
  XCTAssertFalse(ChatGPTRequestFailure.unusableRefresh(nil))
 }
 func testErrorCodeSanitizationDoesNotEchoServerProseOrTokens() {
  XCTAssertEqual(ChatGPTRequestFailure.code(in:["error":["code":"insufficient_scopes"]]),"insufficient_scopes")
  XCTAssertNil(ChatGPTRequestFailure.code(in:["error":["code":"Bearer secret-token"]]))
  XCTAssertNil(ChatGPTRequestFailure.code(in:["error":"https://example.com/?token=secret"]))
 }
 func testConnectivityDoesNotSendSecretsOrPerformInference() async {
  ProbeProtocol.lock.lock();ProbeProtocol.requests=[];ProbeProtocol.fail=false;ProbeProtocol.lock.unlock()
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ProbeProtocol.self];config.httpShouldSetCookies=false;config.httpCookieStorage=nil
  let session=URLSession(configuration:config);defer {session.invalidateAndCancel()}
  let results=await ChatGPTConnectivity.check(session:session)
  XCTAssertEqual(results.map(\.reachable),[true,true])
  ProbeProtocol.lock.lock();let requests=ProbeProtocol.requests;ProbeProtocol.lock.unlock()
  XCTAssertEqual(requests.count,2)
  for request in requests {XCTAssertEqual(request.httpMethod,"GET");XCTAssertNil(request.httpBody);XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"));XCTAssertFalse(request.url!.path.contains("responses"))}
 }
 func testConnectivityTimeoutIsReportedWithoutInferenceRetry() async {
  ProbeProtocol.lock.lock();ProbeProtocol.requests=[];ProbeProtocol.fail=true;ProbeProtocol.lock.unlock()
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ProbeProtocol.self]
  let session=URLSession(configuration:config);defer {session.invalidateAndCancel()}
  let results=await ChatGPTConnectivity.check(session:session)
  XCTAssertEqual(results.map(\.reachable),[false,false]);XCTAssertTrue(results.allSatisfy{$0.message.contains("超时")})
  ProbeProtocol.lock.lock();let count=ProbeProtocol.requests.count;ProbeProtocol.lock.unlock()
  XCTAssertEqual(count,2)
 }
}
private final class ProbeProtocol:URLProtocol {
 static let lock=NSLock()
 static var requests:[URLRequest]=[]
 static var fail=false
 override class func canInit(with request:URLRequest)->Bool {true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading() {
  Self.lock.lock();Self.requests.append(request);let fail=Self.fail;Self.lock.unlock()
  if fail {client?.urlProtocol(self,didFailWithError:URLError(.timedOut));return}
  let code=request.url!.host=="auth.openai.com" ? 200:401
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:nil)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
