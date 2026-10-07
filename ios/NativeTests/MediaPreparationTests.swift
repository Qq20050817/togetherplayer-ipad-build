import XCTest
import AVFoundation
import PrismCore
import UIKit
import UniformTypeIdentifiers
@testable import TogetherPoC

final class MediaPreparationTests: XCTestCase {
 @MainActor func testPickerMP4SelectionDeliversOnceWithoutCopying() {
  var selected:[URL]=[];var cancellations=0
  let picker=LocalMovieDocumentPicker(onPick:{selected.append($0)},onCancel:{cancellations += 1})
  let coordinator=picker.makeCoordinator()
  let controller=UIDocumentPickerViewController(forOpeningContentTypes:LocalMovieDocumentPicker.contentTypes,asCopy:false)
  let url=URL(fileURLWithPath:"/tmp/movie.MP4")
  coordinator.documentPicker(controller,didPickDocumentsAt:[url])
  coordinator.documentPicker(controller,didPickDocumentsAt:[url])
  coordinator.documentPickerWasCancelled(controller)
  XCTAssertEqual(selected,[url]);XCTAssertEqual(cancellations,0)
  XCTAssertTrue(LocalMovieDocumentPicker.contentTypes.contains(.mpeg4Movie))
  XCTAssertFalse(LocalMovieDocumentPicker.contentTypes.contains(.folder))
 }
 @MainActor func testPickerCancelIsDeliveredOnlyOnce() {
  var selections=0;var cancellations=0
  let picker=LocalMovieDocumentPicker(onPick:{_ in selections += 1},onCancel:{cancellations += 1})
  let coordinator=picker.makeCoordinator()
  let controller=UIDocumentPickerViewController(forOpeningContentTypes:LocalMovieDocumentPicker.contentTypes,asCopy:false)
  coordinator.documentPickerWasCancelled(controller)
  coordinator.documentPicker(controller,didPickDocumentsAt:[URL(fileURLWithPath:"/tmp/movie.mp4")])
  XCTAssertEqual(selections,0);XCTAssertEqual(cancellations,1)
 }
 @MainActor func testLocalSelectionSurvivesFilePickerBackgroundAndReconnect() async throws {
  UserDefaults.standard.removeObject(forKey:"credentials")
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try TestMovieFixture.mp4.write(to:url);defer {try? FileManager.default.removeItem(at:url)}
  let model=TestClient()
  var fixture=roomFixture();fixture["mediaUrl"]="https://example.org/movie.mp4"
  model.receive(["type":"WELCOME","room":fixture],t4:0)
  model.beginLocalFileSelection()
  model.handleBackground()
  model.useLocalFile(url)
  XCTAssertTrue(model.requestStatus.contains("恢复房间连接"))
  model.receive(["type":"WELCOME","room":fixture],t4:0)
  for _ in 0..<100 {
   if (model.adapter.player.currentItem?.asset as? AVURLAsset)?.url==url {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertTrue(model.usingLocalFile)
  XCTAssertEqual((model.adapter.player.currentItem?.asset as? AVURLAsset)?.url,url)
 }
 @MainActor func testLocalSameFileMatchesButDifferentBytesRequireConfirmation() async throws {
  UserDefaults.standard.removeObject(forKey:"credentials")
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try Data("hello".utf8).write(to:url);defer {try? FileManager.default.removeItem(at:url)}
  let model=TestClient();var fixture=roomFixture()
  fixture["mediaUrl"]="baidu://"+String(repeating:"b",count:32)+"/f08c3fe9dd10774cc643aff6d17165ab/5"
  model.receive(["type":"WELCOME","room":fixture],t4:0)
  model.beginLocalFileSelection();model.useLocalFile(url)
  try await Task.sleep(nanoseconds:100_000_000)
  XCTAssertTrue(model.usingLocalFile)
  model.clearLocalFileSource()
  try Data("world".utf8).write(to:url)
  model.beginLocalFileSelection();model.useLocalFile(url)
  try await Task.sleep(nanoseconds:100_000_000)
  XCTAssertFalse(model.usingLocalFile)
  XCTAssertTrue(model.requestStatus.contains("文件指纹不同"))
  XCTAssertNotNil(model.localQualityCandidate)
  XCTAssertNil(model.adapter.player.currentItem)
  model.cancelLocalQuality();XCTAssertNil(model.localQualityCandidate)
 }
 func testPlayingWithThirtyFiveSecondsCachedIgnoresStaleEmptyHint() {
  let value=readiness(playing:true,bufferedMs:35000)
  XCTAssertTrue(value.ready);XCTAssertFalse(value.buffering)
 }
 func testPausedWithContiguousDataIsReadyDespiteEmptyHint() {
  let value=readiness(bufferedMs:35000)
  XCTAssertTrue(value.ready);XCTAssertFalse(value.buffering)
 }
 func testActualWaitingCannotBeHiddenByLoadedRanges() {
  let value=readiness(waiting:true,bufferedMs:35000)
  XCTAssertFalse(value.ready);XCTAssertTrue(value.buffering)
 }
 func testActualEmptyPausedBufferStillBlocksReadiness() {
  let value=readiness(bufferedMs:0)
  XCTAssertFalse(value.ready);XCTAssertTrue(value.buffering)
 }
 func testRecoveryReserveCanReleaseNativeWaitingForScheduledResume() {
  let value=readiness(waiting:true,bufferedMs:35000,recovering:true)
  XCTAssertTrue(value.ready);XCTAssertFalse(value.buffering)
 }
 func testUnpreparedItemCannotBecomeReadyFromBufferHints() {
  let value=readiness(prepared:false,playing:true,bufferedMs:35000)
  XCTAssertFalse(value.ready)
 }
 func testPlaybackAtEndDoesNotReportAnotherBufferingEpisode() {
  let value=PlaybackReadinessPolicy.evaluate(prepared:true,waiting:false,playing:false,bufferEmpty:true,bufferedMs:0,positionMs:100000,durationMs:100000,recovering:false)
  XCTAssertTrue(value.ready);XCTAssertFalse(value.buffering)
 }
 func testUnknownDurationDoesNotPretendAnEmptyBufferIsFinished() {
  let value=PlaybackReadinessPolicy.evaluate(prepared:true,waiting:false,playing:false,bufferEmpty:true,bufferedMs:0,positionMs:0,durationMs:0,recovering:false)
  XCTAssertFalse(value.ready);XCTAssertTrue(value.buffering)
 }
 private func readiness(prepared: Bool=true,waiting: Bool=false,playing: Bool=false,bufferedMs: Double,recovering: Bool=false) -> PlaybackReadiness {
  PlaybackReadinessPolicy.evaluate(prepared:prepared,waiting:waiting,playing:playing,bufferEmpty:true,bufferedMs:bufferedMs,positionMs:160000,durationMs:6111765,recovering:recovering)
 }
 @MainActor func testRepeatedPausedTicksDoNotInterruptPrerollWithRepeatedPauseCalls() {
  let player=PauseCountingPlayer();let adapter=AVPlayerAdapter(player:player)
  adapter.play();adapter.pause();let count=player.pauseCalls
  for _ in 0..<100 {adapter.pause()}
  XCTAssertEqual(player.pauseCalls,count)
 }
 func testAutomaticRecoveryRequiresReserveAndAllowsShortTail() {
  XCTAssertFalse(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:3000,positionMs:10000,durationMs:100000,recovering:true))
  XCTAssertTrue(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:12000,positionMs:10000,durationMs:100000,recovering:true))
  XCTAssertTrue(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:1950,positionMs:98000,durationMs:100000,recovering:true))
  XCTAssertFalse(RecoveryBufferPolicy.ready(prepared:false,bufferedMs:12000,positionMs:10000,durationMs:100000,recovering:true))
 }

 @MainActor func testPeriodicSnapshotsDoNotRestartPendingMKVPreparation() async throws {
  UserDefaults.standard.removeObject(forKey:"credentials")
  var starts=0
  var pending: CheckedContinuation<URL,Error>?
  let model=TestClient(compatibilityPreparation:{_,_ in
   starts += 1
   return try await withCheckedThrowingContinuation {pending=$0}
  })
  let fixture=roomFixture()
  model.receive(["type":"WELCOME","room":fixture],t4:0)
  XCTAssertTrue(model.useBaiduSource(URL(string:"https://pan.baidu.com/movie.mkv")!,file:file))
  try await Task.sleep(nanoseconds:20_000_000)
  XCTAssertEqual(starts,1)
  XCTAssertNil(model.adapter.player.currentItem)
  for _ in 0..<50 {model.receive(["type":"STATE","room":fixture],t4:0);await Task.yield()}
  XCTAssertEqual(starts,1,"Repeated snapshots must not cancel the pending remux")
  let completion=try XCTUnwrap(pending)
  let playlist=URL(fileURLWithPath:"/nonexistent-preparation-fixture.m3u8")
  completion.resume(returning:playlist)
  try await Task.sleep(nanoseconds:20_000_000)
  XCTAssertNotNil(model.adapter.player.currentItem,"Completed preparation must install the item")
  XCTAssertEqual((model.adapter.player.currentItem?.asset as? AVURLAsset)?.url,playlist)
 }
 @MainActor func testFailedPreparationStaysFailedUntilExplicitRetry() async throws {
  UserDefaults.standard.removeObject(forKey:"credentials")
  var starts=0
  let model=TestClient(compatibilityPreparation:{_,_ in starts += 1;throw MKVRemux.Failure.preparation})
  let fixture=roomFixture()
  model.receive(["type":"WELCOME","room":fixture],t4:0)
  XCTAssertTrue(model.useBaiduSource(URL(string:"https://pan.baidu.com/movie.mkv")!,file:file))
  try await Task.sleep(nanoseconds:20_000_000)
  XCTAssertEqual(starts,1);XCTAssertTrue(model.requestStatus.contains("准备失败"))
  for _ in 0..<50 {model.receive(["type":"STATE","room":fixture],t4:0);await Task.yield()}
  XCTAssertEqual(starts,1);XCTAssertTrue(model.requestStatus.contains("准备失败"))
  model.retryCompatibility()
  try await Task.sleep(nanoseconds:20_000_000)
  XCTAssertEqual(starts,2)
 }
 @MainActor func testFailureClassificationNeverExposesAccountURL() {
  let secret=URL(string:"https://pan.baidu.com/video?access_token=PRIVATE_SECRET")!
  let cases: [(Error,String)]=[
   (PrismCoreError.originRefused(status:403,url:secret),"HTTP 403"),
   (PrismCoreError.originRateLimited(status:429,retryAfter:5,url:secret),"HTTP 429"),
   (PrismCoreSession.SessionError.startupTimedOut(underlying:nil),"20秒"),
   (PrismCoreError.ffmpeg(code:-123,operation:secret.absoluteString,message:secret.absoluteString),"FFmpeg -123"),
   (NSError(domain:"private",code:1,userInfo:[NSLocalizedDescriptionKey:secret.absoluteString]),"原因未分类")
  ]
  for (error,expected) in cases {
   let text=MKVRemux.safeFailure(error).errorDescription ?? ""
   XCTAssertTrue(text.contains(expected));XCTAssertFalse(text.contains("PRIVATE_SECRET"))
   XCTAssertFalse(text.contains("pan.baidu.com"));XCTAssertFalse(text.contains("access_token"))
  }
 }
 private var file: BaiduFile {BaiduFile(id:1,name:"movie.mkv",path:"/movie.mkv",size:5,fingerprint:String(repeating:"a",count:32),isDirectory:false)}
 private func roomFixture() -> [String:Any] {
  let timeline: [String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  return ["roomId":"preparation-room","hostId":"fixture-host","mediaUrl":"baidu://"+String(repeating:"b",count:32)+"/"+String(repeating:"a",count:32)+"/5","version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
 }
}

private final class PauseCountingPlayer: AVPlayer {
 var pauseCalls=0
 override func pause() {pauseCalls += 1;super.pause()}
}
