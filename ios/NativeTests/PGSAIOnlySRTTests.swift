import XCTest
import AVFoundation
@testable import TogetherPoC

final class PGSAIOnlySRTTests:XCTestCase {
 func testSRTKeepsOriginalPGSTimestampsWithoutModifyingMovie() {
  let transcript=SubtitleDocument([
   SubtitleCue(start:65.125,end:68.75,text:"第一句话"),
   SubtitleCue(start:72.001,end:74.5,text:"第二句话\n第二行")
  ])
  let srt=SubtitleSRTEncoder.encode(transcript)
  XCTAssertTrue(srt.contains("1\n00:01:05,125 --> 00:01:08,750\n第一句话"))
  XCTAssertTrue(srt.contains("2\n00:01:12,001 --> 00:01:14,500\n第二句话\n第二行"))
  XCTAssertEqual(srt.components(separatedBy:"-->").count-1,2)
 }
 func testInvalidTimestampsCannotEnterAIOnlySRT() {
  let transcript=SubtitleDocument([
   SubtitleCue(start:.nan,end:5,text:"无效"),SubtitleCue(start:9,end:8,text:"倒序"),
   SubtitleCue(start:0,end:1,text:"有效")
  ])
  let output=SubtitleSRTEncoder.encode(transcript)
  XCTAssertTrue(output.contains("00:00:00,000 --> 00:00:01,000"))
  XCTAssertFalse(output.contains("无效"))
  XCTAssertFalse(output.contains("倒序"))
 }
 @MainActor func testPGSAIOCRPreferenceIsPersistentAndDefaultsEnabled() {
  let name="pgs-ai-only-tests-"+UUID().uuidString
  guard let defaults=UserDefaults(suiteName:name) else {XCTFail("Missing test preferences");return}
  defer {defaults.removePersistentDomain(forName:name)}
  let model=ExternalSubtitles(player:AVPlayer(),preferences:defaults)
  XCTAssertTrue(model.convertPGSForAI)
  model.convertPGSForAI=false
  XCTAssertEqual(defaults.object(forKey:"plot-pgs-ai-srt-enabled") as? Bool,false)
  let reopened=ExternalSubtitles(player:AVPlayer(),preferences:defaults)
  XCTAssertFalse(reopened.convertPGSForAI)
 }
 @MainActor func testAIOnlyOCRIndexDoesNotSelectOrReplacePlaybackTrack() {
  let player=AVPlayer()
  let subtitles=ExternalSubtitles(player:player)
  let cues=SubtitleDocument([SubtitleCue(start:0,end:2,text:"PGS OCR 得到的内容")])
  let before=player.currentItem
  subtitles.installNativeIndex(cues,track:0,forAIOnly:true)
  XCTAssertTrue(subtitles.nativeIndexAIOnly)
  XCTAssertEqual(subtitles.nativeIndexedTrack,0)
  XCTAssertNotNil(subtitles.nativeAISRT)
  XCTAssertTrue(subtitles.nativeAISRT?.contains("PGS OCR 得到的内容") == true)
  XCTAssertFalse(subtitles.enabled,"AI OCR must not enable the external playback subtitle layer")
  XCTAssertTrue(player.currentItem === before,"AI OCR must not replace the movie's AVPlayerItem")
  subtitles.nativeSelectionChanged()
  XCTAssertNil(subtitles.nativeAISRT)
  XCTAssertFalse(subtitles.nativeIndexAIOnly)
 }
}
