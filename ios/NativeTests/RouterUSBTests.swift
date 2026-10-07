import XCTest
import Foundation
@testable import TogetherPoC

private final class USBProtocol: URLProtocol {
 static var handler: ((URLRequest) throws -> (Int,[String:Any]))?
 override class func canInit(with request: URLRequest) -> Bool {true}
 override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
 override func startLoading() {
  do {
   guard let handler=Self.handler else {throw URLError(.badServerResponse)}
   let (status,body)=try handler(request)
   let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json","Set-Cookie":"sid=test-session; Path=/; HttpOnly; SameSite=Strict"])!
   client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
   client?.urlProtocol(self,didLoad:try JSONSerialization.data(withJSONObject:body))
   client?.urlProtocolDidFinishLoading(self)
  } catch {client?.urlProtocol(self,didFailWithError:error)}
 }
 override func stopLoading() {}
}
final class RouterUSBTests: XCTestCase {
 override func tearDown() {USBProtocol.handler=nil;super.tearDown()}
 @MainActor private func client() -> RouterUSB {
  let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[USBProtocol.self]
  return RouterUSB(session:URLSession(configuration:c))
 }
 private func state(_ authenticated:Bool=false) -> [String:Any] { ["authenticated":authenticated,"needsSetup":false,"safeEjectAvailable":true,"csrf":"before"] }
 @MainActor func testAuthenticatedEjectRotatesCSRFAndPreservesCookie() async throws {
  var paths:[String]=[]
  USBProtocol.handler={request in
   let path=request.url!.path;paths.append(path)
   XCTAssertEqual(request.url?.host,"192.168.31.1");XCTAssertEqual(request.url?.port,49186)
   if path=="/api/session" {return(200,self.state())}
   XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),"http://192.168.31.1:49186")
   XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"sid=test-session")
   if path=="/api/login" {
    XCTAssertEqual(request.value(forHTTPHeaderField:"X-CSRF-Token"),"before")
    return(200,["authenticated":true,"csrf":"after"])
   }
   XCTAssertEqual(path,"/api/eject");XCTAssertEqual(request.httpMethod,"POST")
   XCTAssertEqual(request.value(forHTTPHeaderField:"X-CSRF-Token"),"after")
   return(200,["safeToRemove":true,"mediaServiceRestartRequested":true])
  }
  let model=client();await model.eject(password:"test-only-password")
  XCTAssertEqual(paths,["/api/session","/api/login","/api/eject"])
  XCTAssertTrue(model.safeToRemove);XCTAssertFalse(model.working);XCTAssertTrue(model.status.contains("可以拔出"))
 }
 @MainActor func testWrongPasswordNeverRequestsEject() async {
  var paths:[String]=[]
  USBProtocol.handler={request in
   paths.append(request.url!.path)
   if request.url!.path=="/api/session" {return(200,self.state())}
   return(400,["error":"authentication_failed"])
  }
  let model=client();await model.eject(password:"incorrect")
  XCTAssertEqual(paths,["/api/session","/api/login"]);XCTAssertFalse(model.safeToRemove)
  XCTAssertTrue(model.status.contains("密码不正确"));XCTAssertTrue(model.status.contains("请勿拔出"))
 }
 @MainActor func testBusyUSBAndFalseSuccessCannotClaimRemovable() async {
  for response in [(409,["error":"usb_busy_or_unmount_failed"] as [String:Any]),(200,["safeToRemove":false] as [String:Any])] {
   USBProtocol.handler={request in request.url!.path=="/api/session" ? (200,self.state(true)) : response}
   let model=client();await model.eject(password:"")
   XCTAssertFalse(model.safeToRemove);XCTAssertTrue(model.status.contains("请勿拔出"))
  }
 }
 @MainActor func testAlreadyAuthenticatedCanEjectWithoutSendingPasswordAgain() async {
  var paths:[String]=[]
  USBProtocol.handler={request in
   paths.append(request.url!.path)
   return request.url!.path=="/api/session" ? (200,self.state(true)) : (200,["safeToRemove":true])
  }
  let model=client();await model.eject(password:"")
  XCTAssertTrue(model.safeToRemove);XCTAssertEqual(paths,["/api/session","/api/eject"])
 }
 @MainActor func testNetworkFailureIsNotReportedAsSafe() async {
  USBProtocol.handler={_ in throw URLError(.timedOut)}
  let model=client();await model.eject(password:"test-only-password")
  XCTAssertFalse(model.safeToRemove);XCTAssertFalse(model.working);XCTAssertTrue(model.status.contains("未确认安全卸载"))
 }
}
