import XCTest
import AVFoundation
@testable import TogetherPoC

final class PGSOverlayWiringTests: XCTestCase {
 @MainActor func testAITextIndexCannotCreateOriginalBitmapFrame() {
  let subtitles=ExternalSubtitles(player:AVPlayer())
  let aiText=SubtitleDocument([SubtitleCue(start:0,end:4,text:"OCR 后的文字")])
  subtitles.installNativeIndex(aiText,track:0,forAIOnly:true)
  XCTAssertTrue(subtitles.nativeIndexAIOnly)
  XCTAssertNotNil(subtitles.nativeAISRT)
  XCTAssertNil(subtitles.originalPGSFrame,
               "OCR SRT must never masquerade as an original PGS bitmap")
 }
 @MainActor func testOriginalBitmapTimelineDoesNotReplaceAITextOrPlaybackMovie() {
  let player=AVPlayer()
  let subtitles=ExternalSubtitles(player:player)
  let text=SubtitleDocument([SubtitleCue(start:0,end:4,text:"仅供 AI OCR")])
  subtitles.installNativeIndex(text,track:0,forAIOnly:true)
  let originalSRT=subtitles.nativeAISRT
  let frame=PGSBitmapFrame(videoWidth:100,videoHeight:50,objects:[
   PGSBitmapObject(x:2,y:3,width:1,height:1,indices:[0],
                   paletteARGB:[0xFFFFFFFF])
  ])
  let before=player.currentItem
  subtitles.installOriginalPGS([PGSBitmapEvent(time:0,frame:frame)],track:0)
  XCTAssertEqual(subtitles.nativeAISRT,originalSRT)
  XCTAssertTrue(player.currentItem === before)
  XCTAssertFalse(subtitles.enabled)
  subtitles.nativeSelectionChanged(enabled:false)
  XCTAssertNil(subtitles.originalPGSFrame)
  XCTAssertNil(subtitles.nativeAISRT)
 }
}
