import XCTest
@testable import TogetherPoC
final class FullscreenSpeedTests:XCTestCase {
 final class Player:PlayerAdapter {
  var position=0.0;var duration=100000.0;var buffering=false;var ready=true
  var rate:Float=1;var playing=false;var seeks=0
  func play(){playing=true};func pause(){playing=false};func seekTo(_ ms:Double){seeks += 1;position=ms};func setPlaybackSpeed(_ speed:Float){rate=speed}
 }
 func testScheduledRoomPlayStartsOnceWithoutFirstSecondHardSeek() {
  var now=0.0
  let clock=ClockSync{now};clock.add(0,0,0,0)
  let p=Player();p.position=0
  let engine=SyncEngine(p,clock)
  let paused=Timeline(state:"paused",position:0,updatedAt:0,playbackRate:1)
  let before=Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:1,executeAt:0,state:"paused",position:0,updatedAt:0,playbackRate:1,before:paused)
  engine.receive(before)
  now=200
  let scheduled=Room(roomId:"r",hostId:"h",mediaUrl:before.mediaUrl,version:2,executeAt:950,state:"playing",position:2500,updatedAt:950,playbackRate:1,before:paused)
  engine.receive(scheduled)
  now=700;engine.tick();XCTAssertFalse(p.playing,"scheduled start should not start early")
  now=1000;engine.tick();XCTAssertTrue(p.playing)
  XCTAssertEqual(p.seeks,0,"the first frame must not trigger a catch-up seek")
  XCTAssertEqual(p.rate,1,"startup correction must not interrupt decoding")
  now=1800;p.position=100;engine.tick()
  XCTAssertEqual(p.seeks,0,"short startup stalls should not cause another seek")
  now=3300;engine.tick()
  XCTAssertEqual(p.seeks,1,"genuine sustained drift should still be corrected")
 }
 func testSharedRateUsesExecuteAtAndRestoresWithoutSeek() {
  var now=1000.0;let clock=ClockSync{now};clock.add(0,0,0,0)
  let p=Player();let engine=SyncEngine(p,clock)
  let before=Timeline(state:"playing",position:1000,updatedAt:1000,playbackRate:1)
  engine.receive(Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:2,executeAt:1150,state:"playing",position:1150,updatedAt:1150,playbackRate:2,before:before))
  p.position=1000;engine.tick();XCTAssertEqual(p.rate,1)
  now=1250;p.position=1350;engine.tick();XCTAssertEqual(p.rate,2)
  engine.receive(Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:3,executeAt:1250,state:"playing",position:1350,updatedAt:1250,playbackRate:1,before:before))
  engine.tick();XCTAssertEqual(p.rate,1);XCTAssertEqual(p.position,1350)
 }
}
