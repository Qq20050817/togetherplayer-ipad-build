import XCTest
@testable import TogetherPoC

private final class USBManagementProtocol: URLProtocol {
 static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
 override class func canInit(with request: URLRequest) -> Bool {true}
 override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
 override func startLoading() {
  do {
   let (code, body) = try Self.handler!(request)
   let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
   client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
   client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
   client?.urlProtocolDidFinishLoading(self)
  } catch {client?.urlProtocol(self, didFailWithError: error)}
 }
 override func stopLoading() {}
}

@MainActor final class RouterUSBManagementTests: XCTestCase {
 private func manager(deleteResult: [String:Any], code: Int = 200) -> RouterUSBManagement {
  USBManagementProtocol.handler = {request in
   switch request.url!.path {
   case "/api/session": return (200, ["authenticated":true,"csrf":"test-token","deleteAvailable":true])
   case "/api/list": return (200, ["items":[["name":"测试.mkv","path":"电影/测试.mkv","directory":false,"bytes":123,"version":"v1"]],"hasMore":false])
   case "/api/delete":
    XCTAssertEqual(request.httpMethod,"POST")
    XCTAssertEqual(request.value(forHTTPHeaderField:"X-CSRF-Token"),"test-token")
    XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),"http://192.168.31.1:49186")
    return (code,deleteResult)
   default: throw URLError(.badURL)
   }
  }
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [USBManagementProtocol.self]
  return RouterUSBManagement(session: URLSession(configuration: config))
 }
 func testOnlyVerifiedMatchingSuccessRemovesRow() async {
  let model = manager(deleteResult:["deleted":true,"path":"电影/测试.mkv"])
  await model.login(password: "")
  XCTAssertTrue(model.authenticated)
  XCTAssertEqual(model.items.count,1)
  await model.delete(model.items[0])
  XCTAssertTrue(model.items.isEmpty)
  XCTAssertTrue(model.status.contains("已删除并核验"))
 }
 func testReadOnlyErrorRetainsRow() async {
  let model = manager(deleteResult:["error":"usb_read_only"],code:409)
  await model.login(password: "")
  await model.delete(model.items[0])
  XCTAssertEqual(model.items.count,1)
  XCTAssertTrue(model.status.contains("只读"))
 }
 func testMismatchingAcknowledgementDoesNotReportSuccess() async {
  let model = manager(deleteResult:["deleted":true,"path":"other.mkv"])
  await model.login(password: "")
  await model.delete(model.items[0])
  XCTAssertEqual(model.items.count,1)
  XCTAssertTrue(model.status.contains("未确认删除成功"))
 }
}
