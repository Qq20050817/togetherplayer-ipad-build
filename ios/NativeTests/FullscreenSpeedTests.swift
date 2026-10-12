import XCTest
@testable import TogetherPoC
final class FullscreenSpeedTests:XCTestCase {
 final class Player:PlayerAdapter {
  var position=0.0;var duration=100000.0;var buffering=false;var ready=true
  var rate:Float=1;var playing=false
  func play(){playing=true};func pause(){playing=false};func seekTo(_ ms:Double){position=ms};func setPlaybackSpeed(_ speed:Float){rate=speed}
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
