import XCTest
@testable import TogetherPoC

final class VoiceSessionRecoveryTests:XCTestCase {
 @MainActor func testPlaybackActionFeedbackPublishesImmediately() {
  let feedback=ClientFeedback();feedback.showPlaybackAction("正在同步暂停…")
  XCTAssertEqual(feedback.playbackAction,"正在同步暂停…")
  feedback.showPlaybackAction("正在同步跳转…");XCTAssertEqual(feedback.playbackAction,"正在同步跳转…")
 }
 @MainActor func testSharedPlaybackSessionDriftIsRepairedOnNextHold() {
  var current=false;var activations=0;var restores=0
  let session=VoiceRecordingSession(isCurrent:{current},activate:{activations+=1;current=true},release:{restores+=1;current=false})
  let capture=VoiceCapture(session:session)
  XCTAssertTrue(capture.prepareSession());XCTAssertEqual(activations,1)
  capture.stop(restoreSession:false)
  XCTAssertTrue(capture.prepareSession());XCTAssertEqual(activations,1)
  // A movie/browser changed the shared session back to playback.
  current=false
  XCTAssertTrue(capture.prepareSession());XCTAssertEqual(activations,2)
  XCTAssertFalse(capture.status.contains("已关闭"))
  capture.stop();XCTAssertEqual(restores,1)
 }
 @MainActor func testFailedSessionPreparationReportsErrorAndCanRetry() {
  var fails=true;var restores=0
  let session=VoiceRecordingSession(isCurrent:{false},activate:{if fails {throw NSError(domain:"capture-test",code:7,userInfo:[NSLocalizedDescriptionKey:"设备暂不可用"])}},release:{restores+=1})
  let capture=VoiceCapture(session:session)
  XCTAssertFalse(capture.prepareSession());XCTAssertTrue(capture.status.contains("设备暂不可用"));XCTAssertEqual(restores,1)
  fails=false
  XCTAssertTrue(capture.prepareSession());XCTAssertFalse(capture.status.contains("失败"));capture.stop()
 }
 @MainActor func testControlsStayVisibleDuringTouchAndOverlappingModals() async throws {
  let controls=FullscreenControlState(delay:0.06)
  controls.schedule();controls.beginInteraction();controls.setBusy("voice",true);controls.setBusy("volume",true)
  try await Task.sleep(nanoseconds:100_000_000);XCTAssertTrue(controls.visible)
  controls.setBusy("volume",false);controls.endInteraction()
  try await Task.sleep(nanoseconds:100_000_000);XCTAssertTrue(controls.visible)
  controls.setBusy("voice",false)
  try await Task.sleep(nanoseconds:100_000_000);XCTAssertFalse(controls.visible)
 }
 @MainActor func testIdleDeadlineRestartsAfterInteraction() async throws {
  let controls=FullscreenControlState(delay:0.15);controls.schedule()
  try await Task.sleep(nanoseconds:100_000_000);controls.beginInteraction()
  try await Task.sleep(nanoseconds:100_000_000);XCTAssertTrue(controls.visible);controls.endInteraction()
  try await Task.sleep(nanoseconds:80_000_000);XCTAssertTrue(controls.visible)
  try await Task.sleep(nanoseconds:150_000_000);XCTAssertFalse(controls.visible)
 }
 @MainActor func testSlowVoiceDanmakuRetainsTextAndUsesConfiguredSpeed() {
  let previous=UserDefaults.standard.object(forKey:"danmakuSpeed")
  defer {if let value=previous {UserDefaults.standard.set(value,forKey:"danmakuSpeed")} else {UserDefaults.standard.removeObject(forKey:"danmakuSpeed")}}
  UserDefaults.standard.set(0.5,forKey:"danmakuSpeed")
  let chat=ChatEngine();chat.reset("speed-test")
  chat.accept(ChatMessage(id:1,userId:"u",name:"我",text:String(repeating:"字",count:300),clientMessageId:"voice:test",timestamp:0),mine:true,live:true,now:1000)
  XCTAssertEqual(chat.danmaku.first?.durationMs,10000);XCTAssertEqual(chat.danmaku.first?.expiresAt,11000)
  XCTAssertTrue(chat.danmaku.first?.text.hasSuffix(String(repeating:"字",count:300)) == true)
  XCTAssertEqual(DanmakuSpeed.duration(10000,speed:2),5000)
  XCTAssertEqual(DanmakuSpeed.duration(10000,speed:.nan),10000)
 }
}
