import XCTest
import AVFoundation
@testable import TogetherPoC

final class RoomConnectionTests: XCTestCase {
 override func tearDown() {UserDefaults.standard.removeObject(forKey:"credentials");super.tearDown()}
 func testConnectionHealthSeparatesHandshakeSilenceAndMissingAcknowledgement() {
  XCTAssertNil(RoomConnectionHealth.timeout(now:19000,connected:false,startedAt:0,lastMessageAt:0,inFlightAt:nil))
  XCTAssertEqual(RoomConnectionHealth.timeout(now:21000,connected:false,startedAt:0,lastMessageAt:20000,inFlightAt:nil),"welcome_timeout")
  XCTAssertNil(RoomConnectionHealth.timeout(now:26000,connected:true,startedAt:0,lastMessageAt:25000,inFlightAt:nil))
  XCTAssertEqual(RoomConnectionHealth.timeout(now:26000,connected:true,startedAt:0,lastMessageAt:0,inFlightAt:nil),"message_timeout")
  XCTAssertNil(RoomConnectionHealth.timeout(now:14000,connected:true,startedAt:0,lastMessageAt:13000,inFlightAt:1000))
  XCTAssertTrue(RoomConnectionHealth.operationExpired(now:14000,sentAt:1000))
  XCTAssertFalse(RoomConnectionHealth.operationExpired(now:13000,sentAt:1000))
 }
 func testEmptyAndMalformedFramesDoNotDecodeAsRoomMessages() {
  for raw in [""," ","not-json","[]","null","{}","{\"kind\":\"pong\"}","{\"type\":7}"] {
   XCTAssertNil(RoomEnvelope.decode(Data(raw.utf8)),raw)
  }
  XCTAssertEqual(RoomEnvelope.decode(Data("{\"type\":\"PONG\",\"t1\":1}".utf8))?["type"] as? String,"PONG")
 }
 func testLargeReconnectWelcomeAndBoundedDecoder() throws {
  var frame=welcome()
  frame["messages"]=(1...36).map { index in
   ["id":index,"userId":"guest","name":"好友",
    "text":String(repeating:"聊天记录",count:80),
    "clientMessageId":"history-\(index)","timestamp":Double(index)] as [String:Any]
  }
  let payload=try JSONSerialization.data(withJSONObject:frame)
  XCTAssertGreaterThan(payload.count,8192)
  XCTAssertLessThan(payload.count,1_048_576)
  XCTAssertEqual(RoomEnvelope.decode(payload)?["type"] as? String,"WELCOME")
  XCTAssertNil(RoomEnvelope.decode(Data(repeating:0x20,count:1_048_577)))
 }
 @MainActor func testBackgroundReconnectAcceptsLargeValidWelcome() throws {
  let model=try client()
  model.receive(welcome(),t4:0)
  model.handleBackground()
  var frame=welcome()
  frame["messages"]=(1...36).map { index in
   ["id":index,"userId":"guest","name":"好友",
    "text":String(repeating:"聊天记录",count:80),
    "clientMessageId":"history-\(index)","timestamp":Double(index)] as [String:Any]
  }
  let payload=try JSONSerialization.data(withJSONObject:frame)
  XCTAssertGreaterThan(payload.count,8192)
  model.receiveFrame(payload,t4:0)
  XCTAssertTrue(model.isConnected)
  XCTAssertEqual(model.engine.room?.roomId,"connection-test")
  XCTAssertEqual(model.chat.messages.count,36)
 }
 func testActiveSceneResumesStaleSocketWithoutRestartingFreshHandshake() {
  func reconnect(_ wasForeground:Bool,_ connected:Bool,_ hasSocket:Bool,_ messageAge:Double,_ connectionAge:Double) -> Bool {
   RoomResumePolicy.shouldReconnect(hasCredentials:true,wasForeground:wasForeground,isConnected:connected,
    hasSocket:hasSocket,lastMessageAgeMs:messageAge,connectionAgeMs:connectionAge)
  }
  XCTAssertFalse(RoomResumePolicy.shouldReconnect(hasCredentials:false,wasForeground:false,isConnected:false,
   hasSocket:false,lastMessageAgeMs:100_000,connectionAgeMs:100_000))
  XCTAssertTrue(reconnect(false,true,true,100,100))
  XCTAssertTrue(reconnect(true,false,false,100,100))
  XCTAssertFalse(reconnect(true,false,true,100,100))
  XCTAssertTrue(reconnect(true,false,true,100,10_000))
  XCTAssertFalse(reconnect(true,true,true,14_999,100_000))
  XCTAssertTrue(reconnect(true,true,true,15_000,100_000))
  XCTAssertFalse(RoomResumePolicy.shouldReconnect(hasCredentials:true,wasForeground:true,isConnected:true,
   hasSocket:true,lastMessageAgeMs:100,connectionAgeMs:500,inactiveDurationMs:2999))
  XCTAssertFalse(RoomResumePolicy.shouldReconnect(hasCredentials:true,wasForeground:true,isConnected:true,
   hasSocket:true,lastMessageAgeMs:100,connectionAgeMs:500,inactiveDurationMs:3000))
  XCTAssertFalse(RoomResumePolicy.shouldReconnect(hasCredentials:true,wasForeground:true,isConnected:false,
   hasSocket:true,lastMessageAgeMs:100,connectionAgeMs:500,inactiveDurationMs:6000))
 }
 func testReconnectFailuresShowSanitizedNetworkReasons() {
  XCTAssertEqual(RoomTransportFailure.description(NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut),httpStatus:nil),"连接超时")
  XCTAssertEqual(RoomTransportFailure.description(NSError(domain:NSURLErrorDomain,code:NSURLErrorNetworkConnectionLost),httpStatus:nil),"网络连接中断")
  XCTAssertEqual(RoomTransportFailure.description(NSError(domain:NSURLErrorDomain,code:NSURLErrorCannotFindHost),httpStatus:nil),"无法解析服务器地址")
  XCTAssertEqual(RoomTransportFailure.description(NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut),httpStatus:503),"服务器入口暂不可用（HTTP 503）")
  XCTAssertEqual(RoomTransportFailure.description(NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut),httpStatus:401),"房间凭证失效（HTTP 401）")
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
 func testForegroundGraceIsIdentityBoundedAndCannotBeRenewedByRetries() {
  var grace=RoomReconnectContinuity()
  XCTAssertFalse(grace.begin(roomID:"room",mediaURL:"movie",now:0,canContinue:false))
  XCTAssertTrue(grace.begin(roomID:"room",mediaURL:"movie",now:1000,canContinue:true))
  XCTAssertTrue(grace.begin(roomID:"room",mediaURL:"movie",now:8000,canContinue:true))
  XCTAssertEqual(grace.deadline,9000)
  XCTAssertFalse(grace.preserves(roomID:"other",mediaURL:"movie",now:8000))
  XCTAssertFalse(grace.preserves(roomID:"room",mediaURL:"other",now:8000))
  XCTAssertFalse(grace.begin(roomID:"room",mediaURL:"movie",now:9000,canContinue:true))
  XCTAssertEqual(grace.deadline,9000)
  grace.reset();XCTAssertNil(grace.deadline)
 }
 func testGraceRejectsNonfiniteClockAndEmptyIdentity() {
  var grace=RoomReconnectContinuity()
  XCTAssertFalse(grace.begin(roomID:"",mediaURL:"movie",now:0,canContinue:true))
  XCTAssertFalse(grace.begin(roomID:"room",mediaURL:"movie",now:.nan,canContinue:true))
  XCTAssertTrue(grace.begin(roomID:"room",mediaURL:"movie",now:0,canContinue:true))
  XCTAssertFalse(grace.preserves(roomID:"room",mediaURL:"movie",now:.infinity))
 }
 @MainActor func testBriefTransportLossKeepsRealPlayerItemAndAdvancingClock() async throws {
  let model=try client()
  defer {model.handleBackground()}
  var playing=room(url:"fixture://continuity")
  playing["state"]="playing"
  model.receive(["type":"WELCOME","room":playing,"lastSequence":0],t4:0)
  let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"room-continuity",withExtension:"mp4"))
  let item=AVPlayerItem(url:url);model.adapter.player.replaceCurrentItem(with:item);model.adapter.player.play()
  for _ in 0..<60 {
   if model.adapter.ready && model.adapter.position>150 {break}
   try await Task.sleep(nanoseconds:50_000_000)
  }
  XCTAssertTrue(model.adapter.ready);XCTAssertGreaterThan(model.adapter.player.rate,0)
  let before=model.adapter.position
  model.disconnectForTest()
  XCTAssertFalse(model.isConnected)
  XCTAssertEqual(model.engine.room?.roomId,"connection-test")
  XCTAssertTrue(model.adapter.player.currentItem === item)
  try await Task.sleep(nanoseconds:250_000_000)
  XCTAssertGreaterThan(model.adapter.position,before+50,"transport loss must not pause decoded playback")
  model.receive(["type":"WELCOME","room":playing,"lastSequence":0],t4:0)
  XCTAssertTrue(model.isConnected)
  XCTAssertTrue(model.adapter.player.currentItem === item,"same-source WELCOME must not reload the decoder")
  XCTAssertGreaterThan(model.adapter.player.rate,0)
 }
 @MainActor func testManualPauseDuringOutageStaysPausedWhileWelcomeCalibrates() async throws {
  let model=try client();defer {model.handleBackground()}
  var playing=room(url:"fixture://offline-pause");playing["state"]="playing"
  model.receive(["type":"WELCOME","room":playing,"lastSequence":0],t4:0)
  let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"room-continuity",withExtension:"mp4"))
  model.adapter.player.replaceCurrentItem(with:AVPlayerItem(url:url));model.adapter.player.play()
  for _ in 0..<60 {
   if model.adapter.ready && model.adapter.position>150 {break}
   try await Task.sleep(nanoseconds:50_000_000)
  }
  XCTAssertTrue(model.adapter.ready)
  model.disconnectForTest();model.control("PAUSE")
  XCTAssertEqual(model.adapter.player.rate,0)
  model.receive(["type":"WELCOME","room":playing,"lastSequence":0],t4:0)
  try await Task.sleep(nanoseconds:150_000_000)
  XCTAssertEqual(model.adapter.player.rate,0,"old playing snapshot must not override the offline user pause")
 }
 @MainActor func testPausedRoomNeverGetsPlaybackGrace() throws {
  let model=try client();defer {model.handleBackground()}
  model.receive(welcome(),t4:0)
  model.disconnectForTest()
  XCTAssertNil(model.engine.room)
  XCTAssertEqual(model.adapter.player.rate,0)
 }
 @MainActor func testMissingCommandAcknowledgementDoesNotCloseHealthyRoom() async throws {
  var now=1000.0;var sent:[[String:Any]]=[]
  let clock=ClockSync{now};let model=try client(sender:{sent.append($0)},clock:clock)
  defer {model.handleBackground()}
  model.receive(["type":"WELCOME","room":room(url:"fixture://ack"),"lastSequence":0],t4:now)
  model.mediaURL="https://example.org/next.mp4";model.movieTitle="Synthetic";model.setRoomMedia()
  XCTAssertTrue(model.isSettingRoomMedia)
  now=14001
  model.receive(["type":"PONG","t1":now,"t2":now,"t3":now],t4:now)
  try await Task.sleep(nanoseconds:200_000_000)
  XCTAssertTrue(model.isConnected,"a timed-out command must not tear down a healthy room")
  XCTAssertEqual(model.engine.room?.roomId,"connection-test")
  XCTAssertFalse(model.isSettingRoomMedia)
  XCTAssertTrue(model.requestStatus.contains("确认超时"))
  XCTAssertTrue(sent.contains {$0["type"] as? String=="SYNC"})
  XCTAssertEqual(sent.filter {$0["type"] as? String=="ROOM_MEDIA"}.count,1,"do not blindly replay a stale command")
 }
 @MainActor func testReconnectGraceExpiryPausesRealPlayerWithoutRenewingWindow() async throws {
  var now=1000.0;let model=try client(clock:ClockSync{now});defer {model.handleBackground()}
  var playing=room(url:"fixture://expiry");playing["state"]="playing"
  model.receive(["type":"WELCOME","room":playing,"lastSequence":0],t4:now)
  let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"room-continuity",withExtension:"mp4"))
  model.adapter.player.replaceCurrentItem(with:AVPlayerItem(url:url));model.adapter.player.play()
  for _ in 0..<60 {
   if model.adapter.ready && model.adapter.position>150 {break}
   try await Task.sleep(nanoseconds:50_000_000)
  }
  XCTAssertTrue(model.adapter.ready);model.disconnectForTest()
  now=9001
  try await Task.sleep(nanoseconds:150_000_000)
  XCTAssertEqual(model.adapter.player.rate,0)
  XCTAssertNil(model.engine.room)
 }
 @MainActor private func client(sender: (([String:Any])->Void)? = nil,clock:ClockSync? = nil) throws -> TestClient {
  let credentials:[String:Any]=["roomId":"connection-test","userId":"host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  return TestClient(automaticallyConnect:false,messageSender:sender ?? {_ in},roomClock:clock)
 }
 private func welcome() -> [String:Any] {["type":"WELCOME","room":room(),"lastSequence":0]}
 private func room(url: String="https://example.org/old.mp4",title: String="旧影片",version: Int=1) -> [String:Any] {
  let timeline:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  return ["roomId":"connection-test","hostId":"host","mediaUrl":url,"title":title,"version":version,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":timeline]
 }
}
