import XCTest
@testable import TogetherPoC

final class P2PMuseHandoffTests: XCTestCase {
 private func hint(_ action:P2PPlaybackAction = .play) -> P2PControlHint {
  P2PControlHint(roomID:"room",senderUserID:"host",roomVersion:7,sequence:1,
                 action:action,positionMs:20_000,issuedAtMs:100_000)
 }
 func testOldRoomSnapshotCannotUndoP2PPlayAndMuseAckTakesOver() {
  var handoff=P2PMuseHandoff()
  handoff.begin(hint(),timelineOffset:0,now:100)
  XCTAssertTrue(handoff.shouldDeferMuse(now:1_400,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:20_000,blockingPoll:false,authoritativePause:false))
  // A server-side PLAY with a future executeAt can still expose 'paused'
  // until its scheduled start. Preserve local first frames in that gap.
  XCTAssertTrue(handoff.shouldDeferMuse(now:1_500,roomID:"room",roomVersion:8,
    targetState:"paused",targetPositionMs:20_000,blockingPoll:false,authoritativePause:false))
  XCTAssertFalse(handoff.shouldDeferMuse(now:1_600,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:20_100,blockingPoll:false,authoritativePause:false))
  XCTAssertFalse(handoff.shouldDeferMuse(now:1_700,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:20_200,blockingPoll:false,authoritativePause:false))
 }
 func testPauseAndSeekHandoff() {
  var handoff=P2PMuseHandoff()
  handoff.begin(hint(.pause),timelineOffset:0,now:100)
  XCTAssertTrue(handoff.shouldDeferMuse(now:300,roomID:"room",roomVersion:7,
    targetState:"playing",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  XCTAssertFalse(handoff.shouldDeferMuse(now:600,roomID:"room",roomVersion:8,
    targetState:"paused",targetPositionMs:20_000,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(.seek),timelineOffset:500,now:1_000)
  XCTAssertTrue(handoff.shouldDeferMuse(now:1_500,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:50_000,blockingPoll:false,authoritativePause:false))
  XCTAssertFalse(handoff.shouldDeferMuse(now:1_600,roomID:"room",roomVersion:8,
    targetState:"playing",targetPositionMs:20_550,blockingPoll:false,authoritativePause:false))
 }
 func testTimeoutAndSafetyStopsAlwaysGiveMuseControlBack() {
  var handoff=P2PMuseHandoff()
  handoff.begin(hint(),timelineOffset:0,now:100)
  XCTAssertFalse(handoff.shouldDeferMuse(now:3_600,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:4_000)
  XCTAssertFalse(handoff.shouldDeferMuse(now:4_100,roomID:"other",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:5_000)
  XCTAssertFalse(handoff.shouldDeferMuse(now:5_100,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:true,authoritativePause:false))
  handoff.begin(hint(),timelineOffset:0,now:6_000)
  XCTAssertFalse(handoff.shouldDeferMuse(now:6_100,roomID:"room",roomVersion:7,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:true))
  handoff.begin(hint(),timelineOffset:0,now:7_000)
  XCTAssertFalse(handoff.shouldDeferMuse(now:7_100,roomID:"room",roomVersion:9,
    targetState:"paused",targetPositionMs:nil,blockingPoll:false,authoritativePause:false))
 }
}
