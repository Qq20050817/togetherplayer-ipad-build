import XCTest
import Foundation
@testable import TogetherPoC

// Simulate a NAS that supports HEAD and 206 byte-range reads. The test never
// relies on an external service or downloads a movie fixture.
final class FilmHTTPRangeMock:URLProtocol {
 static let size=200_000
 override class func canInit(with request:URLRequest)->Bool {
  request.url?.host?.hasSuffix(".film-range.invalid") == true
 }
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading() {
  guard let url=request.url else {client?.urlProtocol(self,didFailWithError:URLError(.badURL));return}
  let head=request.httpMethod=="HEAD"
  let noRange=url.host=="no-range.film-range.invalid"
  var status=200,body=Data()
  var headers=["Content-Length":String(Self.size),
               "ETag":"\"movie-version-1\"",
               "Last-Modified":"Sun, 18 Oct 2026 00:00:00 GMT",
               "Accept-Ranges":"bytes"]
  if !head {
   guard let raw=request.value(forHTTPHeaderField:"Range"),
         raw.hasPrefix("bytes=") else {
    client?.urlProtocol(self,didFailWithError:URLError(.badServerResponse));return
   }
   let parts=raw.dropFirst(6).split(separator:"-")
   guard parts.count==2,let start=Int(parts[0]),let end=Int(parts[1]),
         start>=0,end>=start,end<Self.size else {
    client?.urlProtocol(self,didFailWithError:URLError(.badServerResponse));return
   }
   body=Data((start...end).map{UInt8($0%251)})
   if !noRange {
    status=206
    headers["Content-Length"]=String(body.count)
    headers["Content-Range"]="bytes \(start)-\(end)/\(Self.size)"
   }
  }
  let response=HTTPURLResponse(url:url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:headers)!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  if !body.isEmpty {client?.urlProtocol(self,didLoad:body)}
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}

final class FilmMaterialRemoteTests:XCTestCase {
 private func session()->URLSession {
  let configuration=URLSessionConfiguration.ephemeral
  configuration.protocolClasses=[FilmHTTPRangeMock.self]
  return URLSession(configuration:configuration)
 }
 func testUSBRangeFingerprintStableAcrossSignedURLRefresh() throws {
  let session=session();defer{session.invalidateAndCancel()}
  let a=URL(string:"https://usb.film-range.invalid/media/film.mkv?expires=100&sig=abc")!
  let b=URL(string:"https://usb.film-range.invalid/media/film.mkv?expires=200&sig=xyz")!
  let changed=URL(string:"https://usb.film-range.invalid/media/another-film.mkv?expires=200&sig=xyz")!
  let first=try FilmMaterialFingerprint.remote(a,session:session)
  let again=try FilmMaterialFingerprint.remote(b,session:session)
  let other=try FilmMaterialFingerprint.remote(changed,session:session)
  XCTAssertEqual(first,again,"Refreshing a signed URL should retain a film bank")
  XCTAssertNotEqual(first,other,"Different movie paths must not alias")
  XCTAssertEqual(first.count,64)
 }
 func testHTTPWithout206RangeFailsWithoutFullDownload() throws {
  let session=session();defer{session.invalidateAndCancel()}
  let url=URL(string:"https://no-range.film-range.invalid/film.mkv")!
  XCTAssertThrowsError(try FilmMaterialFingerprint.remote(url,session:session)) {error in
   XCTAssertEqual(error.localizedDescription,FilmMaterialExportFailure.remoteUnavailable.localizedDescription)
  }
 }
 func testOtherURLSchemesNeverAttemptRemoteMaterialRead() throws {
  let session=session();defer{session.invalidateAndCancel()}
  XCTAssertThrowsError(try FilmMaterialFingerprint.remote(URL(string:"ftp://usb.film-range.invalid/movie.mkv")!,session:session))
 }
}
