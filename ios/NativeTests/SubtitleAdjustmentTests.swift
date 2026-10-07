import XCTest
import AVFoundation
@testable import TogetherPoC

final class SubtitleAdjustmentTests:XCTestCase {
 func testNativeCueTimingSupportsEarlierLaterAndBlankEndEvents() {
  var timeline=NativeSubtitleTimeline()
  timeline.receive(text:"原片字幕",time:5);timeline.receive(text:"",time:7)
  XCTAssertEqual(timeline.text(at:5.5),"原片字幕")
  XCTAssertEqual(timeline.text(at:5.5-1),"") // +1: later
  XCTAssertEqual(timeline.text(at:4.5-(-1)),"原片字幕") // -1: earlier
  XCTAssertEqual(timeline.text(at:7),"")
  timeline.clear();XCTAssertEqual(timeline.text(at:6),"")
 }
 func testNativeEventsAreOrderedAndDuplicateTimestampReplacesPayload() {
  var timeline=NativeSubtitleTimeline();timeline.receive(text:"",time:8)
  timeline.receive(text:"old",time:3);timeline.receive(text:"new",time:3)
  XCTAssertEqual(timeline.text(at:4),"new");XCTAssertEqual(timeline.events.count,2)
  XCTAssertEqual(timeline.text(at:.nan),"")
 }
 @MainActor func testFontAndVerticalPositionPersistAndReset() {
  let suite="SubtitleAdjustmentTests-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!;defer {defaults.removePersistentDomain(forName:suite)}
  let subtitles=ExternalSubtitles(player:AVPlayer(),preferences:defaults)
  subtitles.fontSize=40;subtitles.bottomFraction=0.4;subtitles.delay=2
  subtitles.fontFamily = .rounded;subtitles.fontWeight = .light;subtitles.letterSpacing=1.25;subtitles.lineSpacing=8
  let restored=ExternalSubtitles(player:AVPlayer(),preferences:defaults)
  XCTAssertEqual(restored.fontSize,40);XCTAssertEqual(restored.bottomFraction,0.4)
  XCTAssertEqual(restored.fontFamily,.rounded);XCTAssertEqual(restored.fontWeight,.light)
  XCTAssertEqual(restored.letterSpacing,1.25);XCTAssertEqual(restored.lineSpacing,8)
  XCTAssertEqual(restored.delay,0,"A different movie must not inherit timing")
  subtitles.resetAdjustments();XCTAssertEqual(subtitles.fontSize,24)
  XCTAssertEqual(subtitles.bottomFraction,0.07);XCTAssertEqual(subtitles.delay,0)
  XCTAssertEqual(subtitles.fontFamily,.system);XCTAssertEqual(subtitles.fontWeight,.regular)
  XCTAssertEqual(subtitles.letterSpacing,0);XCTAssertEqual(subtitles.lineSpacing,0)
 }
 func testAppearanceRejectsInvalidAndOffscreenValues() {
  XCTAssertEqual(SubtitleAppearance.font(.nan),24)
  XCTAssertEqual(SubtitleAppearance.font(1000),64)
  XCTAssertEqual(SubtitleAppearance.position(-1),0.02)
  XCTAssertEqual(SubtitleAppearance.position(.infinity),0.07)
  XCTAssertEqual(SubtitleAppearance.letterSpacing(.nan),0)
  XCTAssertEqual(SubtitleAppearance.letterSpacing(-100),-2)
  XCTAssertEqual(SubtitleAppearance.lineSpacing(100),20)
  XCTAssertEqual(SubtitleAppearance.lineSpacing(-1),0)
 }
}
