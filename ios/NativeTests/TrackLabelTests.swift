import XCTest
import AVFoundation
@testable import TogetherPoC
final class TrackLabelTests:XCTestCase {
 func testSubtitlePositionExcludesLetterboxBars() {
  let container=CGSize(width:1200,height:1000)
  let picture=SubtitlePictureLayout.picture(container:container,presentation:CGSize(width:1920,height:1080))
  XCTAssertEqual(picture.height,675)
  XCTAssertEqual(SubtitlePictureLayout.bottom(container:container,picture:picture,fraction:0.1,textHeight:30,inset:0),230,accuracy:0.01)
 }

 @MainActor func testRealMKVSelectionsRetainCodecLayoutAndChineseScript() async throws {
  let model=TestClient(automaticallyConnect:false)
  try model.installTrackPlaybackFixture()
  for _ in 0..<150 {
   if model.audioLabels.count==2 && model.subtitleLabels.count==2 {break}
   try await Task.sleep(nanoseconds:100_000_000)
  }
  XCTAssertEqual(model.audioLabels.count,2)
  XCTAssertTrue(model.audioLabels.joined().contains("AAC"))
  XCTAssertTrue(model.audioLabels.joined().contains("AC3"))
  XCTAssertTrue(model.audioLabels.joined().contains("5.1"))
  XCTAssertTrue(model.audioLabels.allSatisfy {!$0.contains("English")})
  XCTAssertTrue(model.subtitleLabels.contains {$0.hasPrefix("简体中文")})
  XCTAssertTrue(model.subtitleLabels.contains {$0.hasPrefix("繁体中文")})
  model.chooseSubtitle(1)
  XCTAssertEqual(model.selectedSubtitleIndex,1)
  model.adapter.pause()
 }

 func testChineseScriptIsNotGuessedFromOrder() {
  XCTAssertTrue(TrackLabel.localized("Chinese (CHS)",language:"zh",subtitle:true).hasPrefix("简体中文"))
  XCTAssertTrue(TrackLabel.localized("Chinese",language:"zh-Hant",subtitle:true).hasPrefix("繁体中文"))
  XCTAssertTrue(TrackLabel.localized("Chinese 2",language:"zh",subtitle:true).contains("简繁未标明"))
 }
 func testTitleMetadataRetainsSourceAudioDetail() {
  let label=AudioTrackDetail.label(name:"English [DTS-HD MA · 5.1 · 源音轨 2]",index:1,language:"en",subtypes:["mp4a"],tracks:[],optionCount:2)
  XCTAssertEqual(label,"英语 [DTS-HD MA · 5.1 · 源音轨 2]")
 }
 func testForeignEndonymStillShowsChineseLanguage() {
  XCTAssertTrue(TrackLabel.localized("Français",language:"fr",subtitle:true).hasPrefix("法语"))
 }
 func testTranslatedSubtitleTypes() {
  XCTAssertEqual(TrackLabel.localized("English (SDH)",language:"en",subtitle:true),"英语 (听障字幕)")
 }
}
