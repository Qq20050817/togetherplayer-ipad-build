import XCTest
@testable import TogetherPoC

final class RoomConnectionTests: XCTestCase {
 @MainActor func testStaleSnapshotCannotReloadPreviousFilmOrPollButStillAcknowledgesCommand() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)})
  model.receive(welcome(),t4:0)
  model.mediaURL="https://example.org/current.mp4";model.movieTitle="当前影片"
  model.setRoomMedia()
  let sequence=try XCTUnwrap(sent.first { $0["type"] as? String == "ROOM_MEDIA" }?["sequence"] as? Int64)
  let current=room(url:model.mediaURL,title:model.movieTitle,version:3)
  model.receive(["type":"STATE","room":current,"poll":["id":"current-poll","question":"当前题目"]],t4:0)
  XCTAssertTrue(model.isSettingRoomMedia)
  model.receive(["type":"STATE","room":room(version:2),"poll":NSNull(),
   "ackUserId":"host","ackSequence":sequence],t4:0)
  XCTAssertEqual(model.engine.room?.version,3)
  XCTAssertEqual(model.mediaURL,"https://example.org/current.mp4")
  XCTAssertEqual(model.roomTitle,"当前影片")
  XCTAssertEqual(model.plotPoll?["id"] as? String,"current-poll")
  XCTAssertFalse(model.isSettingRoomMedia,"An old snapshot must not block a valid command ACK")
 }
 @MainActor func testSameVersionRefreshAndNewRoomWithLowerVersionRemainAccepted() throws {
  let model=try client()
  model.receive(["type":"WELCOME","room":room(version:5)],t4:0)
  model.receive(["type":"STATE","room":room(title:"刷新标题",version:5)],t4:0)
  XCTAssertEqual(model.roomTitle,"刷新标题")
  var next=room(title:"新房间",version:1);next["roomId"]="another-room"
  model.receive(["type":"WELCOME","room":next],t4:0)
  XCTAssertEqual(model.engine.room?.roomId,"another-room")
  XCTAssertEqual(model.roomTitle,"新房间")
 }
 override func tearDown() {UserDefaults.standard.removeObject(forKey:"credentials");super.tearDown()}
 func testConnectionHealthSeparatesHandshakeSilenceAndMissingAcknowledgement() {
  XCTAssertNil(RoomConnectionHealth.timeout(now:19000,connected:false,startedAt:0,lastMessageAt:0,inFlightAt:nil))
  XCTAssertEqual(RoomConnectionHealth.timeout(now:21000,connected:false,startedAt:0,lastMessageAt:20000,inFlightAt:nil),"welcome_timeout")
  XCTAssertNil(RoomConnectionHealth.timeout(now:26000,connected:true,startedAt:0,lastMessageAt:25000,inFlightAt:nil))
  XCTAssertEqual(RoomConnectionHealth.timeout(now:26000,connected:true,startedAt:0,lastMessageAt:0,inFlightAt:nil),"message_timeout")
  XCTAssertEqual(RoomConnectionHealth.timeout(now:14000,connected:true,startedAt:0,lastMessageAt:13000,inFlightAt:1000),"ack_timeout")
 }
 func testEmptyAndMalformedFramesDoNotDecodeAsRoomMessages() {
  for raw in [""," ","not-json","[]","null","{}","{\"kind\":\"pong\"}","{\"type\":7}"] {
   XCTAssertNil(RoomEnvelope.decode(Data(raw.utf8)),raw)
  }
  XCTAssertEqual(RoomEnvelope.decode(Data("{\"type\":\"PONG\",\"t1\":1}".utf8))?["type"] as? String,"PONG")
 }
 @MainActor func testInvalidFramesDoNotDisconnectOrLoseFollowingSnapshot() throws {
  let model=try client();model.receive(welcome(),t4:0)
  for raw in ["","not-json","[]"] {model.receiveFrame(Data(raw.utf8),t4:0)}
  XCTAssertTrue(model.isConnected)
  var state=room();state["version"]=2
  model.receiveFrame(try JSONSerialization.data(withJSONObject:["type":"STATE","room":state]),t4:0)
  XCTAssertEqual(model.engine.room?.version,2)
 }
 @MainActor func testRoomMediaSendsWithoutPlaybackClockAndConfirmsOnlyOnAck() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)});model.receive(welcome(),t4:0)
  XCTAssertFalse(model.clock.ready)
  model.mediaURL="https://example.org/new.mp4";model.movieTitle=" 新影片 "
  model.setRoomMedia();model.setRoomMedia()
  let commands=sent.filter {$0["type"] as? String=="ROOM_MEDIA"}
  XCTAssertEqual(commands.count,1);XCTAssertTrue(model.isSettingRoomMedia)
  XCTAssertTrue(model.mediaFeedback.requestStatus.contains("等待服务器确认"))
  let sequence=try XCTUnwrap(commands.first?["sequence"] as? Int64)
  let state=room(url:model.mediaURL,title:"新影片",version:2)
  model.receive(["type":"STATE","room":state,"ackUserId":"host","ackSequence":sequence-1],t4:0)
  XCTAssertTrue(model.isSettingRoomMedia)
  model.receive(["type":"STATE","room":state,"ackUserId":"host","ackSequence":sequence],t4:0)
  XCTAssertFalse(model.isSettingRoomMedia)
  XCTAssertTrue(model.mediaFeedback.requestStatus.contains("已设置"))
 }
 @MainActor func testReconnectResendsUnappliedMediaButDoesNotReplayAlreadyAppliedChange() throws {
  for applied in [false,true] {
   var sent:[[String:Any]]=[]
   let model=try client(sender:{sent.append($0)});model.receive(welcome(),t4:0)
   model.mediaURL="https://example.org/new.mp4";model.movieTitle="新影片";model.setRoomMedia()
   model.handleBackground()
   let snapshot=applied ? room(url:model.mediaURL,title:model.movieTitle,version:2) : room()
   model.receive(["type":"WELCOME","room":snapshot,"lastSequence":applied ? 1 : 0],t4:0)
   let commands=sent.filter {$0["type"] as? String=="ROOM_MEDIA"}
   XCTAssertEqual(commands.count,applied ? 1 : 2)
   XCTAssertEqual(model.isSettingRoomMedia,!applied)
  }
 }
 @MainActor func testPendingChangeCannotApplyToDifferentRoom() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)});model.receive(welcome(),t4:0)
  model.mediaURL="https://example.org/new.mp4";model.setRoomMedia();model.handleBackground()
  var next=room();next["roomId"]="another-room"
  model.receive(["type":"WELCOME","room":next],t4:0)
  XCTAssertEqual(sent.filter {$0["type"] as? String=="ROOM_MEDIA"}.count,1)
  XCTAssertFalse(model.isSettingRoomMedia);XCTAssertTrue(model.mediaFeedback.requestStatus.contains("房间或房主已改变"))
 }
 @MainActor func testMediaChosenWhileDisconnectedWaitsForOriginalRoomWelcome() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)});model.receive(welcome(),t4:0);model.handleBackground()
  model.mediaURL="https://example.org/new.mp4";model.movieTitle="断线期间选择";model.setRoomMedia()
  XCTAssertTrue(model.isSettingRoomMedia);XCTAssertTrue(model.mediaFeedback.requestStatus.contains("等待房间重连"))
  XCTAssertTrue(sent.filter {$0["type"] as? String=="ROOM_MEDIA"}.isEmpty)
  model.receive(welcome(),t4:0)
  XCTAssertEqual(sent.filter {$0["type"] as? String=="ROOM_MEDIA"}.count,1)
 }
 @MainActor func testMediaValidationAndServerRejectionAppearBesideAction() throws {
  let model=try client();model.receive(welcome(),t4:0)
  model.mediaURL="https://example.org/new.mp4?access_token=PRIVATE";model.setRoomMedia()
  XCTAssertTrue(model.mediaFeedback.requestStatus.contains("账户凭据"));XCTAssertFalse(model.isSettingRoomMedia)
  model.mediaURL="https://example.org/new.mp4";model.setRoomMedia()
  model.receive(["type":"ERROR","error":"INVALID_SOURCE","room":room()],t4:0)
  XCTAssertFalse(model.isSettingRoomMedia);XCTAssertTrue(model.mediaFeedback.requestStatus.contains("片源"))
 }
 @MainActor func testStaleVersionRetriesWithLatestSnapshotOnce() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)});model.receive(welcome(),t4:0)
  model.mediaURL="https://example.org/new.mp4";model.setRoomMedia()
  model.receive(["type":"ERROR","error":"STALE_VERSION","room":room(version:2)],t4:0)
  let commands=sent.filter {$0["type"] as? String=="ROOM_MEDIA"}
  XCTAssertEqual(commands.count,2);XCTAssertEqual(commands.last?["baseVersion"] as? Int64,2)
  model.receive(["type":"ERROR","error":"STALE_VERSION","room":room(version:3)],t4:0)
  XCTAssertFalse(model.isSettingRoomMedia)
  XCTAssertEqual(sent.filter {$0["type"] as? String=="ROOM_MEDIA"}.count,2)
 }

 @MainActor func testRapidDuplicatePlayIsSentOnlyOnceUntilAcknowledgement() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)})
  model.receive(welcome(),t4:0)
  let now=model.clock.localNow()
  model.clock.add(now,now,now,now)
  model.control("PLAY")
  model.control("PLAY")
  model.control("PLAY")
  XCTAssertEqual(sent.filter{($0["type"] as? String)=="PLAY"}.count,1)
  XCTAssertTrue(model.feedback.playbackAction.contains("处理中"))
 }
 @MainActor func testTwoMembersHostPlayQueuesOneControlWithoutResettingRoom() throws {
  var sent:[[String:Any]]=[]
  let model=try client(sender:{sent.append($0)})
  model.receive(welcome(),t4:0)
  let host=RoomMember(userId:"host",name:"房主",timelineOffset:0,
   duration:1800000,position:0,ready:true,buffering:false,online:true)
  let guest=RoomMember(userId:"guest",name:"好友",timelineOffset:0,
   duration:1800000,position:0,ready:true,buffering:false,online:true)
  let roster=try JSONSerialization.jsonObject(with:JSONEncoder().encode([host,guest]))
  model.receive(["type":"PRESENCE","members":roster],t4:0)
  XCTAssertEqual(model.members.count,2)
  XCTAssertTrue(model.isRoomHost)
  let now=model.clock.localNow()
  model.clock.add(now,now+100,now+100,now+200)
  XCTAssertTrue(model.clock.ready)
  model.control("PLAY")
  let commands=sent.filter {$0["type"] as? String == "PLAY"}
  XCTAssertEqual(commands.count,1)
  XCTAssertTrue(model.isConnected)
  XCTAssertEqual(model.engine.room?.roomId,"connection-test")
 }
 @MainActor private func client(sender: (([String:Any])->Void)? = nil) throws -> TestClient {
  let credentials:[String:Any]=["roomId":"connection-test","userId":"host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  return TestClient(automaticallyConnect:false,messageSender:sender ?? {_ in})
 }
 private func welcome() -> [String:Any] {["type":"WELCOME","room":room(),"lastSequence":0]}
 private func room(url: String="https://example.org/old.mp4",title: String="旧影片",version: Int=1) -> [String:Any] {
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  return ["roomId":"connection-test","hostId":"host","mediaUrl":url,"title":title,"version":version,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
 }
}
