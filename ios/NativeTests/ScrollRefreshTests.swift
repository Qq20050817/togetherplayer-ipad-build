import XCTest
import Combine
@testable import TogetherPoC

@MainActor final class ScrollRefreshTests:XCTestCase {
 private func frame(position:Double=0,version:Int=1,state:String="paused",name:String="好友")->[String:Any] {
  let timeline:[String:Any]=["state":state,"position":0,"updatedAt":0,"playbackRate":1]
  return ["type":"STATE","poll":NSNull(),"room":["roomId":"scroll-test","hostId":"fixture-host","mediaUrl":"fixture://scroll","version":version,"executeAt":0,"state":state,"position":0,"updatedAt":0,"playbackRate":1,"before":timeline],"members":[["userId":"peer","name":name,"timelineOffset":0,"duration":600000,"position":position,"ready":true,"buffering":false,"online":true]]]
 }
 private func connect(_ model:TestClient) {
  var initial=frame();initial["type"]="WELCOME"
  model.receive(initial,t4:0)
 }
 func testHealthyConnectedTimerKeepsSynchronizingWithoutInvalidatingPages() async throws {
  var sent:[[String:Any]]=[]
  let model=TestClient(automaticallyConnect:false,messageSender:{sent.append($0)})
  connect(model);sent=[]
  var invalidations=0
  let observation=model.objectWillChange.sink {invalidations+=1}
  defer {observation.cancel()}
  try await Task.sleep(nanoseconds:1_300_000_000)
  XCTAssertTrue(sent.contains{$0["type"] as? String=="SYNC"},"the sync timer must still run during UI isolation")
  XCTAssertTrue(sent.contains{$0["type"] as? String=="PLAYER_STATUS"})
  XCTAssertEqual(invalidations,0,"healthy/paused checks must not force ten whole-page redraws per second")
 }
 func testPositionSnapshotsUpdateRosterWithoutRefreshingEveryPage() {
  let model=TestClient(automaticallyConnect:false);connect(model)
  var pages=0;var roster=0
  let a=model.objectWillChange.sink {pages+=1}
  let b=model.roster.objectWillChange.sink {roster+=1}
  defer {a.cancel();b.cancel()}
  for index in 1...200 {model.receive(frame(position:Double(index*1000)),t4:0)}
  XCTAssertEqual(pages,0,"unchanged poll and changing member positions are not whole-page state changes")
  XCTAssertEqual(roster,200)
  XCTAssertEqual(model.members.first?.position,200000)
  model.receive(frame(position:201000,name:"新昵称"),t4:0)
  XCTAssertGreaterThan(pages,0,"membership changes must remain visible")
 }
 func testPeerTransportChangeStillInvalidatesPlaybackControls() {
  let model=TestClient(automaticallyConnect:false);connect(model)
  var changes=0
  let observation=model.objectWillChange.sink {changes+=1}
  defer {observation.cancel()}
  model.receive(frame(version:2,state:"playing"),t4:0)
  XCTAssertGreaterThan(changes,0,"remote playback changes must not depend on the discarded health-check redraws")
  XCTAssertTrue(model.requestedPlaying)
  model.receive(frame(version:3,state:"paused"),t4:0)
  XCTAssertFalse(model.requestedPlaying)
 }
 func testRepeatedPollSnapshotsAreQuietButAnswersAndRemovalUpdate() {
  let model=TestClient(automaticallyConnect:false);connect(model)
  let poll:[String:Any]=["id":"poll","question":"有什么疑点？","options":["动机","说法"],"submitted":[],"answers":[:],"revealed":false]
  model.receive(["type":"PLOT_POLL_STATE","poll":poll],t4:0)
  var changes=0
  let observation=model.objectWillChange.sink {changes+=1}
  defer {observation.cancel()}
  for _ in 0..<100 {model.receive(["type":"PLOT_POLL_STATE","poll":poll],t4:0)}
  XCTAssertEqual(changes,0)
  var answered=poll;answered["submitted"]=["peer"]
  model.receive(["type":"PLOT_POLL_STATE","poll":answered],t4:0)
  XCTAssertGreaterThan(changes,0)
  changes=0
  model.receive(["type":"PLOT_POLL_STATE","poll":NSNull()],t4:0)
  XCTAssertGreaterThan(changes,0);XCTAssertNil(model.plotPoll)
 }
}
