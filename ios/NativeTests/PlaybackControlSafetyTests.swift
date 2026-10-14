import XCTest
import AVFoundation
@testable import TogetherPoC

private final class DeferredSeekPlayer:AVPlayer {
 typealias Completion = @Sendable (Bool)->Void
 var targets:[Double]=[]
 var completions:[Completion]=[]
 var starts=0
 override func play() {starts += 1}
 override func pause() {}
 override func seek(to time:CMTime,toleranceBefore:CMTime,toleranceAfter:CMTime,completionHandler:@escaping @Sendable (Bool)->Void) {
  targets.append(time.seconds);completions.append(completionHandler)
 }
}

@MainActor final class PlaybackControlSafetyTests:XCTestCase {
 private func readyPlayer() async throws -> (DeferredSeekPlayer,URL) {
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try TestMovieFixture.mp4.write(to:url)
  let player=DeferredSeekPlayer(playerItem:AVPlayerItem(url:url))
  for _ in 0..<200 {
   if player.currentItem?.status != .unknown {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertEqual(player.currentItem?.status,.readyToPlay)
  return (player,url)
 }
 private func drainCompletion() async throws {try await Task.sleep(nanoseconds:30_000_000)}
 func testSeekBurstDefersPlayAndRateUntilItsLastCompletion() async throws {
  let (player,url)=try await readyPlayer();defer {try? FileManager.default.removeItem(at:url)}
  let adapter=AVPlayerAdapter(player:player)
  adapter.play();adapter.seekTo(100)
  for index in 1...1000 {adapter.seekTo(Double(index%9+1)*100)}
  adapter.seekTo(900);adapter.setPlaybackSpeed(2);adapter.play()
  XCTAssertEqual(player.targets.count,1)
  XCTAssertEqual(player.starts,1,"no native play while a seek is outstanding")
  XCTAssertEqual(player.defaultRate,1,"decoder rate is deferred until the burst finishes")
  player.completions[0](true);try await drainCompletion()
  XCTAssertEqual(player.targets.count,2)
  XCTAssertEqual(player.targets.last ?? 0,0.9,accuracy:0.001)
  XCTAssertEqual(player.starts,1,"no play between intermediate seek completions")
  player.completions[1](true);try await drainCompletion()
  XCTAssertFalse(adapter.isSeeking);XCTAssertEqual(player.starts,2)
  XCTAssertEqual(player.defaultRate,2)
 }
 func testPauseDuringSeekCancelsResumeWithoutDroppingFinalPosition() async throws {
  let (player,url)=try await readyPlayer();defer {try? FileManager.default.removeItem(at:url)}
  let adapter=AVPlayerAdapter(player:player)
  adapter.play();adapter.seekTo(500);adapter.pause()
  player.completions[0](true);try await drainCompletion()
  XCTAssertFalse(adapter.isSeeking);XCTAssertEqual(player.starts,1)
  adapter.play();XCTAssertEqual(player.starts,2,"explicit play still works after the seek")
 }
 func testOldCompletionCannotClearOrResumeReplacementItemSeek() async throws {
  let (player,url)=try await readyPlayer();defer {try? FileManager.default.removeItem(at:url)}
  let adapter=AVPlayerAdapter(player:player)
  adapter.play();adapter.seekTo(100)
  adapter.resetPendingSeeks()
  let replacement=AVPlayerItem(url:url);player.replaceCurrentItem(with:replacement)
  for _ in 0..<200 {
   if replacement.status != .unknown {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertEqual(replacement.status,.readyToPlay)
  adapter.itemBecameReady(replacement);adapter.seekTo(800)
  XCTAssertEqual(player.targets.count,2)
  player.completions[0](true);try await drainCompletion()
  XCTAssertTrue(adapter.isSeeking,"late completion must not clear the new item's seek")
  XCTAssertEqual(player.starts,1)
  player.completions[1](true);try await drainCompletion()
  XCTAssertFalse(adapter.isSeeking);XCTAssertEqual(player.starts,1)
 }
 func testPauseAcknowledgementKeepsHoldAndImmediatePlayIsARealCommand() async throws {
  let prior=UserDefaults.standard.data(forKey:"credentials")
  let credentials:[String:Any]=["roomId":"pause-hold","userId":"host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  defer {if let prior {UserDefaults.standard.set(prior,forKey:"credentials")} else {UserDefaults.standard.removeObject(forKey:"credentials")}}
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try TestMovieFixture.mp4.write(to:url);defer {try? FileManager.default.removeItem(at:url)}
  var sent:[[String:Any]]=[]
  let model=TestClient(compatibilityPreparation:{_,_ in url},automaticallyConnect:false,messageSender:{sent.append($0)})
  var room:[String:Any]=["roomId":"pause-hold","hostId":"host","mediaUrl":"https://example.org/hold.mkv","version":1,"executeAt":0,"state":"playing","position":0,"updatedAt":model.clock.localNow(),"playbackRate":1,"before":["state":"playing","position":0,"updatedAt":model.clock.localNow(),"playbackRate":1]]
  model.receive(["type":"WELCOME","room":room,"lastSequence":0],t4:model.clock.localNow())
  for _ in 0..<200 {
   if model.adapter.ready {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertTrue(model.adapter.ready)
  let now=model.clock.localNow();model.clock.add(now,now,now,now)
  room["updatedAt"]=now;room["before"]=["state":"playing","position":0,"updatedAt":now,"playbackRate":1]
  model.receive(["type":"STATE","room":room],t4:now)
  model.control("PAUSE")
  let pause=try XCTUnwrap(sent.last(where:{$0["type"] as? String=="PAUSE"}))
  room["version"]=2;room["state"]="paused";room["executeAt"]=now+750;room["updatedAt"]=now+750
  model.receive(["type":"STATE","room":room,"ackUserId":"host","ackSequence":pause["sequence"]!],t4:now)
  XCTAssertTrue(model.holdingLocalPause,"an ACK must not resume the previous playing timeline")
  model.control("PLAY")
  XCTAssertTrue(sent.contains(where:{$0["type"] as? String=="PLAY"}),"resume after a pending PAUSE must go to the server, not just wake the local player")
  XCTAssertFalse(model.holdingLocalPause)
 }
}
