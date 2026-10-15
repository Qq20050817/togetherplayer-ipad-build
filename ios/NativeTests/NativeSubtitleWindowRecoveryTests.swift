import XCTest
import AVFoundation
@testable import TogetherPoC

final class NativeSubtitleWindowRecoveryTests:XCTestCase {
 func testRecoveryFetchesOnlySelectedCurrentSubtitleSegment() async throws {
  let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[SubtitleWindowProtocol.self]
  let session=URLSession(configuration:configuration);defer{session.invalidateAndCancel()}
  SubtitleWindowProtocol.reset()
  let master=URL(string:"http://127.0.0.1:8123/master.m3u8")!
  let document=await NativeSubtitleIndexReader.fetchCurrentWindow(master:master,track:1,at:9,session:session)
  XCTAssertEqual(document?.cues.first?.text,"当前选中字幕恢复了")
  XCTAssertEqual(document?.cues.first?.start,9)
  XCTAssertEqual(Set(SubtitleWindowProtocol.paths()),["/master.m3u8","/selected/index.m3u8","/selected/current.vtt"])
  XCTAssertFalse(document?.cues.contains(where:{$0.text.contains("future")}) ?? true)
 }
 func testRecoveryDoesNotFetchRemoteMoviesOrFutureSegments() async {
  SubtitleWindowProtocol.reset()
  XCTAssertTrue(NativeSubtitleIndexReader.currentSegments([],at:.nan).isEmpty)
  let future=NativeSubtitleIndexReader.Segment(url:URL(string:"http://127.0.0.1/future.vtt")!,start:12,duration:4)
  XCTAssertTrue(NativeSubtitleIndexReader.currentSegments([future],at:9).isEmpty)
  let document=await NativeSubtitleIndexReader.fetchCurrentWindow(master:URL(string:"https://example.com/master.m3u8")!,track:0,at:9)
  XCTAssertNil(document);XCTAssertTrue(SubtitleWindowProtocol.paths().isEmpty)
 }
 @MainActor func testNativeAdvanceFollowsActualDelayInsteadOfAlwaysReadingTwoMinutesAhead() {
  XCTAssertEqual(ExternalSubtitles.nativeAdvance(for:0),0.5)
  XCTAssertEqual(ExternalSubtitles.nativeAdvance(for:-5),5.5)
  XCTAssertEqual(ExternalSubtitles.nativeAdvance(for:5),0.5)
  XCTAssertEqual(ExternalSubtitles.nativeAdvance(for:-120),120)
 }
 @MainActor func testLaterTimedWindowRestoresCaptionsWithoutSeekOrTrackChange() async throws {
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try TestMovieFixture.mp4.write(to:url);defer{try? FileManager.default.removeItem(at:url)}
  let item=AVPlayerItem(url:url),player=AVPlayer()
  player.replaceCurrentItem(with:item)
  let subtitles=ExternalSubtitles(player:player);subtitles.attachNativeOutput(to:item)
  for _ in 0..<100 {if item.status != .unknown {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertEqual(item.status,.readyToPlay)
  subtitles.recoverCurrentNativeWindow(SubtitleDocument([SubtitleCue(start:0,end:0.3,text:"第一句")]),for:item)
  XCTAssertEqual(subtitles.text,"第一句")
  await player.seek(to:CMTime(seconds:0.7,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
  let before=player.currentTime().seconds
  subtitles.recoverCurrentNativeWindow(SubtitleDocument([SubtitleCue(start:0.6,end:0.95,text:"后面的字幕恢复")]),for:item)
  XCTAssertEqual(subtitles.text,"后面的字幕恢复")
  XCTAssertEqual(player.currentTime().seconds,before,accuracy:0.02)
  XCTAssertEqual(player.rate,0)
  subtitles.nativeSelectionChanged(enabled:false)
  subtitles.recoverCurrentNativeWindow(SubtitleDocument([SubtitleCue(start:0,end:1,text:"不得重新打开关闭的字幕")]),for:item)
  XCTAssertEqual(subtitles.text,"")
 }
}

private final class SubtitleWindowProtocol:URLProtocol {
 private static let lock=NSLock()
 private static var visited:[String]=[]
 static func reset(){lock.withLock{visited=[]}}
 static func paths()->[String]{lock.withLock{visited}}
 override class func canInit(with request:URLRequest)->Bool {request.url?.host=="127.0.0.1"}
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading() {
  let path=request.url!.path
  Self.lock.withLock{Self.visited.append(path)}
  let body:String
  switch path {
  case "/master.m3u8":body="#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,URI=\"other/index.m3u8\"\n#EXT-X-MEDIA:TYPE=SUBTITLES,URI=\"selected/index.m3u8\"\n"
  case "/selected/index.m3u8":body="#EXTM3U\n#EXTINF:8,\npast.vtt\n#EXTINF:4,\ncurrent.vtt\n#EXTINF:4,\nfuture.vtt\n#EXT-X-ENDLIST\n"
  case "/selected/current.vtt":body="WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n当前选中字幕恢复了\n"
  default:body="WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nfuture must not be fetched\n"
  }
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading(){}
}
