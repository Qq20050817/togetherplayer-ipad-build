import XCTest
@testable import TogetherPoC
final class ThreeSecondSyncTests:XCTestCase {
 final class Player:PlayerAdapter {
  var position=10000.0;var duration=1000000.0;var ready=true;var buffering=false
  var running=true
  var nativePlaybackRunning:Bool {running}
  var rate:Float=1;var playing=false;var seeks=0
  func play(){playing=true};func pause(){playing=false}
  func seekTo(_ value:Double){position=value;seeks+=1}
  func setPlaybackSpeed(_ value:Float){rate=value}
 }
 func frame(_ position:Double=10000,_ version:Int64=1,_ at:Double=0)->Room {
  Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:version,executeAt:at,state:"playing",position:position,updatedAt:at,playbackRate:1,before:Timeline(state:"playing",position:10000,updatedAt:0,playbackRate:1))
 }
 func testOnlyContinuousGreaterThanFiveSecondLagAccelerates() {
  var p=SustainedCatchupPolicy()
  for t in 0...100 {XCTAssertEqual(p.speed(error:5000,now:Double(t)*100),1)}
  for t in 0..<50 {XCTAssertEqual(p.speed(error:5001,now:10100+Double(t)*100),1)}
  XCTAssertGreaterThan(p.speed(error:5001,now:15100),1)
  XCTAssertGreaterThan(p.speed(error:4000,now:15200),1)
  XCTAssertEqual(p.speed(error:3000,now:15300),1)
 }
 func testTransientLagAndMissingSamplesRestartContinuousWindow() {
  var p=SustainedCatchupPolicy()
  for t in 0..<50 {XCTAssertEqual(p.speed(error:6000,now:Double(t)*100),1)}
  XCTAssertEqual(p.speed(error:5000,now:5000),1)
  for t in 0..<50 {XCTAssertEqual(p.speed(error:6000,now:5100+Double(t)*100),1)}
  XCTAssertEqual(p.speed(error:6000,now:12000),1)
  for t in 1..<50 {XCTAssertEqual(p.speed(error:6000,now:12000+Double(t)*100),1)}
  XCTAssertGreaterThan(p.speed(error:6000,now:17000),1)
 }
 func testLeadingDeviceNeverAutomaticallyPausesOrSlows() {
  let c=ClockSync{0};c.add(0,0,0,0);let p=Player();let e=SyncEngine(p,c);e.receive(frame());e.tick()
  for gap in [5000.0,9000,10000,11000,20000] {p.position=10000+gap;e.tick();XCTAssertTrue(p.playing);XCTAssertEqual(p.rate,1);XCTAssertEqual(p.seeks,0)}
 }
 func testExplicitSeekAndPauseOverrideActiveCatchup() {
  var now=0.0;let c=ClockSync{now};c.add(0,0,0,0);let p=Player();let e=SyncEngine(p,c);e.receive(frame());e.tick()
  for t in 0...50 {now=Double(t)*100;p.position=10000+now-6000;e.tick()};XCTAssertGreaterThan(p.rate,1)
  e.receive(frame(12000,2,now));e.tick();XCTAssertEqual(p.seeks,1);XCTAssertEqual(p.position,12000);XCTAssertEqual(p.rate,1)
  let paused=Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:3,executeAt:now,state:"paused",position:12000,updatedAt:now,playbackRate:1,before:Timeline(state:"playing",position:12000,updatedAt:now,playbackRate:1))
  p.ready=false;e.receive(paused);e.tick();XCTAssertFalse(p.playing)
 }
 func testInvalidSamplesAndResetNeverCountAsPersistentDrift() {
  var p=SustainedCatchupPolicy();for t in 0...50 {_=p.speed(error:7000,now:Double(t)*100)}
  XCTAssertEqual(p.speed(error:.nan,now:5100),1);XCTAssertEqual(p.speed(error:7000,now:5200),1)
  p.reset();XCTAssertEqual(p.speed(error:7000,now:10000),1);XCTAssertEqual(p.speed(error:-20000,now:10100),1)
 }
 func testToleranceAndSustainedCatchupNeverHardSeek() {
  var now=0.0;let c=ClockSync{now};c.add(0,0,0,0);let p=Player();let e=SyncEngine(p,c);e.receive(frame());e.tick()
  for gap in [-3000.0,-1000,0,1000,3000,4000,5000] {p.position=10000-gap;e.tick();XCTAssertEqual(p.rate,1);XCTAssertEqual(p.seeks,0)}
  for t in 0...50 {now=Double(t)*100;p.position=10000+now-6000;e.tick()};XCTAssertGreaterThan(p.rate,1);XCTAssertEqual(p.seeks,0)
  p.position=10000+now-3000;e.tick();XCTAssertEqual(p.rate,1)
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
