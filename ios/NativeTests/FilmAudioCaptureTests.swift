import XCTest
@testable import TogetherPoC

final class FilmAudioCaptureTests:XCTestCase {
 func testHTTPSOnlyAndNoCredentialInURL() {
  let secret=String(repeating:"x",count:40)
  XCTAssertNoThrow(try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org",secret:secret))
  XCTAssertNoThrow(try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org:10000/v1/audio-capture-asr",secret:secret))
  XCTAssertThrowsError(try FilmAudioCaptureConfiguration(endpoint:"http://capture.example.org",secret:secret))
  XCTAssertThrowsError(try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org/path",secret:secret))
  XCTAssertThrowsError(try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org/v1/audio-capture",secret:secret))
  XCTAssertThrowsError(try FilmAudioCaptureConfiguration(endpoint:"https://user:pass@capture.example.org",secret:secret))
  XCTAssertThrowsError(try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org?a=secret",secret:secret))
  XCTAssertThrowsError(try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org",secret:"short"))
 }

 func testIsolatedRouteUsesOnlyStagingPath() throws {
  let secret=String(repeating:"a",count:40)
  let stage=try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org:10000/v1/audio-capture-asr",secret:secret)
  let url=stage.resourceURL(["v1","audio-capture","sessions"])
  XCTAssertEqual(url.absoluteString,"https://capture.example.org:10000/v1/audio-capture-asr/sessions")
  let plain=try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org",secret:secret)
  XCTAssertEqual(plain.resourceURL(["v1","audio-capture","sessions"]).absoluteString,
                 "https://capture.example.org/v1/audio-capture/sessions")
 }

 func testPairingConfigEncodesAndDecodesWithoutRemoteAccess() throws {
  let setting=try FilmAudioCaptureConfiguration(endpoint:"https://capture.example.org",
                                               secret:String(repeating:"z",count:40))
  let encoded=try JSONEncoder().encode(setting)
  let restored=try JSONDecoder().decode(FilmAudioCaptureConfiguration.self,from:encoded)
  XCTAssertEqual(setting,restored)
  XCTAssertEqual(restored.baseURL.scheme,"https")
 }
}
