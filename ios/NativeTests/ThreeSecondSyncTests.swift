import XCTest
@testable import TogetherPoC
final class ThreeSecondSyncTests:XCTestCase {
 final class Player:PlayerAdapter {
  var position=10000.0;var duration=1000000.0;var ready=true;var buffering=false
  var rate:Float=1;var playing=false;var seeks=0
  func play(){playing=true};func pause(){playing=false}
  func seekTo(_ value:Double){position=value;seeks+=1}
  func setPlaybackSpeed(_ value:Float){rate=value}
 }
 func frame(_ position:Double=10000,_ version:Int64=1,_ at:Double=0)->Room {
  Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:version,executeAt:at,state:"playing",position:position,updatedAt:at,playbackRate:1,before:Timeline(state:"playing",position:10000,updatedAt:0,playbackRate:1))
 }
 func testToleranceAndCatchupNeverHardSeek() {
  let c=ClockSync{0};c.add(0,0,0,0);let p=Player();let e=SyncEngine(p,c)
  e.receive(frame());e.tick()
  for gap in [-3000.0,-1000,0,1000,3000] {p.position=10000-gap;e.tick();XCTAssertEqual(p.rate,1);XCTAssertEqual(p.seeks,0)}
  p.position=6000;e.tick();XCTAssertGreaterThan(p.rate,1);XCTAssertEqual(p.seeks,0)
  p.position=9500;e.tick();XCTAssertEqual(p.rate,1)
 }
 func testSmallScheduledManualSeekBypassesToleranceOnce() {
  var now=0.0;let c=ClockSync{now};c.add(0,0,0,0);let p=Player();let e=SyncEngine(p,c)
  e.receive(frame());e.tick();e.receive(frame(12000,2,750))
  now=500;e.tick();XCTAssertEqual(p.seeks,0)
  now=750;e.tick();XCTAssertEqual(p.seeks,1);XCTAssertEqual(p.position,12000)
  e.receive(frame(12000,2,750));e.tick();XCTAssertEqual(p.seeks,1)
  e.receive(frame(10000,1));e.tick();XCTAssertEqual(p.position,12000)
 }
 func testLoadingRetainsNewestExplicitTargetAndOffset() {
  let c=ClockSync{0};c.add(0,0,0,0);let p=Player();let e=SyncEngine(p,c)
  e.receive(frame());e.tick();p.ready=false;e.timelineOffset=500
  e.receive(frame(20000,2));e.tick();e.receive(frame(80000,3));e.tick()
  XCTAssertEqual(p.seeks,0);p.ready=true;e.tick()
  XCTAssertEqual(p.seeks,1);XCTAssertEqual(p.position,80500)
 }
}
