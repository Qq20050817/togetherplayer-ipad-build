import XCTest
import AVFoundation
@testable import TogetherPoC

final class VoiceDanmakuTests:XCTestCase {
 func testRecognitionAndReleaseNeverSendUntilConfirmation() {
  var gate=VoiceSendGate();var sent:[String]=[]
  gate.begin(room:"r");gate.text="正在说话"
  XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
  gate.finish();XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
  gate.review("结果");XCTAssertTrue(sent.isEmpty)
  gate.text="修改后的结果"
  XCTAssertTrue(gate.confirm(room:"r",send:{sent.append($0);return true}))
  XCTAssertEqual(sent,["修改后的结果"])
  XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
 }
 func testCancellationAndRoomChangesPreventAccidentalSend() {
  var gate=VoiceSendGate();gate.begin(room:"old");gate.finish();gate.review("hello")
  XCTAssertFalse(gate.confirm(room:"new",send:{_ in XCTFail("wrong room");return true}))
  gate.cancel();gate.review("late callback")
  XCTAssertFalse(gate.confirm(room:"old",send:{_ in XCTFail("cancelled");return true}))
 }
 func testEmptyLongAndFailedTransportRemainUnsent() {
  var gate=VoiceSendGate();gate.begin(room:"r");gate.finish();gate.review(" ")
  XCTAssertFalse(gate.confirm(room:"r",send:{_ in XCTFail("empty");return true}))
  gate.text=String(repeating:"字",count:301)
  XCTAssertFalse(gate.confirm(room:"r",send:{_ in XCTFail("long");return true}))
  gate.text="valid";XCTAssertFalse(gate.confirm(room:"r",send:{_ in false}))
  XCTAssertEqual(gate.phase,.review)
 }
 func testTwentyConfirmedMessagesAreSentOnce() {
  var gate=VoiceSendGate();var sent:[String]=[]
  for n in 0..<20 {
   gate.begin(room:"r");gate.finish();gate.review("message \(n)")
   XCTAssertTrue(gate.confirm(room:"r",send:{sent.append($0);return true}))
   XCTAssertFalse(gate.confirm(room:"r",send:{sent.append($0);return true}))
  }
  XCTAssertEqual(sent.count,20);XCTAssertEqual(Set(sent).count,20)
 }
 func testThresholdBlocksQuietInputAndPreservesShortSpeechTail() {
  var gate=VoiceNoiseGate(threshold:0.02)
  XCTAssertFalse(gate.accepts(rms:0.005,now:1))
  XCTAssertTrue(gate.accepts(rms:0.02,now:2))
  XCTAssertTrue(gate.accepts(rms:0.001,now:2.1))
  XCTAssertFalse(gate.accepts(rms:0.001,now:2.21))
  XCTAssertFalse(gate.accepts(rms:.nan,now:3))
 }
 @MainActor func testSmoothVolumeRestoreDoesNotStartOrSeekPlayer() async throws {
  let player=AVPlayer();player.volume=0.8
  let ducker=VoiceVolumeDucker(player:player);ducker.begin()
  try await Task.sleep(nanoseconds:120_000_000)
  XCTAssertGreaterThan(player.volume,0.176);XCTAssertLessThan(player.volume,0.8)
  XCTAssertEqual(player.rate,0)
  ducker.end();try await Task.sleep(nanoseconds:400_000_000)
  XCTAssertEqual(player.volume,0.8,accuracy:0.001);XCTAssertEqual(player.rate,0)
 }
}
