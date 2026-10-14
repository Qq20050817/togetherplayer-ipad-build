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
 func testBlockedMainActorCoalescesRefreshesAndAcceptsNextPulse() async throws {
  let pulse=MainActorPulse()
  var refreshes=0
  for _ in 0..<1000 {pulse.request {refreshes+=1}}
  XCTAssertEqual(refreshes,0)
  try await drainCompletion()
  XCTAssertEqual(refreshes,1,"stale timer updates must not form a backlog")
  pulse.request {refreshes+=1}
  try await drainCompletion()
  XCTAssertEqual(refreshes,2,"coalescing must not stop future refreshes")
 }
 func testRecoveryPrerollRejectsPlayingWaitingAndControlTransitions() {
  XCTAssertFalse(RecoveryBufferPolicy.canPreroll(prepared:true,pausedIntent:false,nativePaused:true,controlPending:false),"scheduled play is not a safe preroll window")
  XCTAssertFalse(RecoveryBufferPolicy.canPreroll(prepared:true,pausedIntent:true,nativePaused:false,controlPending:false),"buffering or playing must not enter preroll")
  XCTAssertFalse(RecoveryBufferPolicy.canPreroll(prepared:true,pausedIntent:true,nativePaused:true,controlPending:true),"a pending seek/pause must settle first")
  XCTAssertFalse(RecoveryBufferPolicy.canPreroll(prepared:false,pausedIntent:true,nativePaused:true,controlPending:false))
  XCTAssertTrue(RecoveryBufferPolicy.canPreroll(prepared:true,pausedIntent:true,nativePaused:true,controlPending:false))
 }
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
 func testGuestInstantControlsChangeIntentBeforeAcknowledgement() async throws {
  let prior=UserDefaults.standard.data(forKey:"credentials")
  let credentials:[String:Any]=["roomId":"instant-test","userId":"guest","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  defer {if let prior {UserDefaults.standard.set(prior,forKey:"credentials")} else {UserDefaults.standard.removeObject(forKey:"credentials")}}
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try TestMovieFixture.mp4.write(to:url);defer {try? FileManager.default.removeItem(at:url)}
  var sent:[[String:Any]]=[]
  let model=TestClient(compatibilityPreparation:{_,_ in url},automaticallyConnect:false,messageSender:{sent.append($0)})
  let now=model.clock.localNow()
  var room:[String:Any]=["roomId":"instant-test","hostId":"host","mediaUrl":"https://example.org/movie.mkv","version":1,"executeAt":now,"state":"paused","position":0,"updatedAt":now,"playbackRate":1,"before":["state":"paused","position":0,"updatedAt":now,"playbackRate":1]]
  model.receive(["type":"WELCOME","instantControlVersion":1,"room":room,"lastSequence":0],t4:now)
  for _ in 0..<200 {if model.adapter.ready {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertTrue(model.adapter.ready)
  let current=model.clock.localNow();model.clock.add(current,current,current,current)
  model.control("PLAY")
  XCTAssertTrue(model.requestedPlaying,"guest playback intent must change before server ACK")
  let command=try XCTUnwrap(sent.first(where:{$0["type"] as? String=="INSTANT_CONTROL"}))
  XCTAssertEqual((command["data"] as? [String:Any])?["type"] as? String,"PLAY")
  XCTAssertFalse(sent.contains(where:{$0["type"] as? String=="CONTROL_REQUEST"}))
  model.control("PAUSE");XCTAssertFalse(model.requestedPlaying)
  room["version"]=2;room["state"]="playing";room["executeAt"]=current;room["updatedAt"]=current
  model.receive(["type":"STATE","instantControlVersion":1,"room":room,"ackUserId":"guest","ackSequence":command["sequence"]!],t4:current)
  XCTAssertFalse(model.requestedPlaying,"an older PLAY acknowledgement must not erase the newer PAUSE")
  let latest=try XCTUnwrap(sent.last(where:{$0["type"] as? String=="INSTANT_CONTROL"}))
  XCTAssertEqual((latest["data"] as? [String:Any])?["type"] as? String,"PAUSE")
 }

}
