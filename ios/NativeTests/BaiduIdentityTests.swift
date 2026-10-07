import XCTest
import Foundation
@testable import TogetherPoC

final class BaiduIdentityTests: XCTestCase {
 func testEmptyDetailDoesNotOverwriteValidListMetadata() {
  let file=BaiduFile(id:1,name:"movie.mkv",path:"/movie.mkv",size:6800248966,fingerprint:String(repeating:"a",count:32),isDirectory:false)
  let merged=BaiduFileIdentity.merge(info:["size":0,"md5":""],file:file)
  XCTAssertEqual(merged.size,file.size);XCTAssertEqual(merged.fingerprint,file.fingerprint)
  XCTAssertEqual(BaiduFileIdentity.size("6800248966"),file.size)
  XCTAssertNil(BaiduFileIdentity.size(-1));XCTAssertNil(BaiduFileIdentity.size(1.5))
  XCTAssertNotNil(BaiduFileIdentity.provider(String(repeating:"g",count:32)))
 }
 func testCrossPlatformSampleIdentityAndDifferentBytes() {
  let samples=[(Int64(0),Data("hello".utf8))]
  XCTAssertEqual(BaiduFileIdentity.sample(size:5,samples:samples),"f08c3fe9dd10774cc643aff6d17165ab")
  XCTAssertNotEqual(BaiduFileIdentity.sample(size:5,samples:samples),BaiduFileIdentity.sample(size:5,samples:[(0,Data("world".utf8))]))
  XCTAssertEqual(BaiduFileIdentity.offsets(size:5),[0])
  XCTAssertEqual(BaiduFileIdentity.offsets(size:200000),[0,67232,134464])
 }
 func testLocalFileSamplingMatchesRoomIdentity() throws {
  let bytes=Data((0..<200000).map {UInt8($0 % 251)})
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mkv")
  try bytes.write(to:url,options:.atomic);defer {try? FileManager.default.removeItem(at:url)}
  let local=try BaiduFileIdentity.localFile(url)
  let samples=BaiduFileIdentity.offsets(size:Int64(bytes.count)).map {offset -> (Int64,Data) in
   let start=Int(offset),end=min(bytes.count,start+65536)
   return (offset,bytes.subdata(in:start..<end))
  }
  XCTAssertEqual(local.size,Int64(bytes.count))
  XCTAssertEqual(local.fingerprint,BaiduFileIdentity.sample(size:Int64(bytes.count),samples:samples))
 }
 func testBoundedReaderAccepts206AndRejectsIgnoredRange() async throws {
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RangeFixture.self]
  let slice=try await BaiduRangeReader.read(URL(string:"https://pan.baidu.com/valid")!,offset:0,count:65536,configuration:config)
  XCTAssertEqual(slice.url.host,"cdn.baidupcs.com");XCTAssertEqual(slice.total,5);XCTAssertEqual(slice.data,Data("hello".utf8))
  do {let _=try await BaiduRangeReader.read(URL(string:"https://pan.baidu.com/untrusted-origin")!,offset:0,count:65536,configuration:config);XCTFail("Untrusted final origin must be rejected")} catch {}
  do {let _=try await BaiduRangeReader.read(URL(string:"https://pan.baidu.com/ignored")!,offset:0,count:65536,configuration:config);XCTFail("HTTP200 must be rejected")} catch {}
  do {let _=try await BaiduRangeReader.read(URL(string:"https://pan.baidu.com/wrong-range")!,offset:0,count:65536,configuration:config);XCTFail("Wrong range must be rejected")} catch {}
 }
 func testRedirectPolicyPreservesRangeAndLimitsHops() {
  let reader=BaiduRangeReader(offset:123,count:456)
  let response=HTTPURLResponse(url:URL(string:"https://pan.baidu.com/source")!,statusCode:302,httpVersion:nil,headerFields:nil)!
  let session=URLSession(configuration:.ephemeral)
  let task=session.dataTask(with:URL(string:"https://pan.baidu.com/source")!)
  defer {session.invalidateAndCancel()}
  for _ in 0..<5 {
   var redirected: URLRequest?
   reader.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:URLRequest(url:URL(string:"https://cdn.baidupcs.com/movie")!)) {redirected=$0}
   XCTAssertEqual(redirected?.value(forHTTPHeaderField:"Range"),"bytes=123-578")
   XCTAssertEqual(redirected?.value(forHTTPHeaderField:"User-Agent"),"pan.baidu.com")
  }
  reader.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:URLRequest(url:URL(string:"https://cdn.baidupcs.com/movie")!)) {XCTAssertNil($0)}
  let other=BaiduRangeReader(offset:0,count:1)
  other.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:URLRequest(url:URL(string:"https://untrusted.example/movie")!)) {XCTAssertNil($0)}
 }

}
private final class RangeFixture: URLProtocol {
 override class func canInit(with request: URLRequest) -> Bool {true}
 override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
 override func startLoading() {
  let path=request.url!.path
  let finalURL=URL(string:path=="/untrusted-origin" ? "https://untrusted.example/movie" : "https://cdn.baidupcs.com/movie")!
  let response=HTTPURLResponse(url:finalURL,statusCode:path=="/ignored" ? 200 : 206,httpVersion:"HTTP/1.1",headerFields:["Content-Range":path=="/wrong-range" ? "bytes 1-4/5" : "bytes 0-4/5"])!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Data("hello".utf8));client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
