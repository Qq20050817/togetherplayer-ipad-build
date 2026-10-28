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

extension FilmAudioCaptureTests {
 func testSelectedSubtitlePayloadIncludesCuesAndTimings() throws {
  let doc=SubtitleDocument((0..<9).map {SubtitleCue(start:Double($0*600),end:Double($0*600+3),text:"字幕内容")})
  let data=try FilmAudioCaptureTransport.subtitlePayload(document:doc,duration:6000)
  let decoded=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
  XCTAssertEqual((decoded["cues"] as? [[String:Any]])?.count,9)
  XCTAssertEqual(decoded["film_duration_seconds"] as? Double,6000)
  XCTAssertNil(decoded["movie_url"])
  XCTAssertNil(decoded["pairing_secret"])
 }
 func testASRCompleteDoesNotMeanSubtitleVerificationPassed() throws {
  let data=Data(#"{"status":"unavailable","received":9,"audio_persisted":false,"asr_status":"complete","recognized_samples":9,"matched_anchors":3}"#.utf8)
  let receipt=try JSONDecoder().decode(FilmAudioCaptureTransport.Receipt.self,from:data)
  let message=FilmAudioCaptureTransport.resultMessage(receipt,hasSubtitles:true)
  XCTAssertTrue(message.contains("证据不足"))
  XCTAssertFalse(message.contains("通过"))
  XCTAssertTrue(message.contains("不能判断是否错位"))
 }
 func testVerifiedReportRequiresEnoughMatchedEvidence() throws {
  for matched in [3,9] {
   let data=Data("{\"status\":\"verified\",\"received\":9,\"audio_persisted\":false,\"recognized_samples\":9,\"matched_anchors\":\(matched)}".utf8)
   let receipt=try JSONDecoder().decode(FilmAudioCaptureTransport.Receipt.self,from:data)
   XCTAssertEqual(FilmAudioCaptureTransport.resultMessage(receipt,hasSubtitles:true).contains("通过"),matched==9)
  }
 }
}
