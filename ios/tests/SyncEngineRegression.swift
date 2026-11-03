import Foundation

final class FakePlayer: PlayerAdapter {
 var position=0.0
 var duration=3_900_000.0
 var buffering=false
 var ready=true
 var rate: Float=1
 var seekCount=0
 var playing=false
 var nativePlaybackRunning=true
 func play() {playing=true}
 func pause() {playing=false}
 func seekTo(_ ms: Double) {seekCount += 1;position=ms}
 func setPlaybackSpeed(_ value: Float) {rate=value}
}

@main struct SyncEngineRegression {
 static func main() {
  var now=0.0
  let clock=ClockSync({now})
  clock.add(0,0,0,0)
  let player=FakePlayer()
  let engine=SyncEngine(player,clock)
  func room(_ state: String="playing",_ version: Int64=1) -> Room {
   Room(roomId:"test",hostId:"host",mediaUrl:"https://example.com/movie.mp4",version:version,executeAt:0,state:state,position:10_000,updatedAt:0,playbackRate:1,before:Timeline(state:state,position:10_000,updatedAt:0,playbackRate:1))
  }
  func error(_ value: Double) {player.position=10_000+now-value;engine.tick()}
  engine.receive(room());player.position=10_000;engine.tick()
  // Old small-drift boundary cycles now remain inside the three-second tolerance.
  for value in [600.0,530,495,510,490,300] {
   now += 100;error(value);precondition(player.rate==1,"fast speed toggled near 500ms")
  }
  error(240);precondition(player.rate==1)
  error(180);precondition(player.rate==1,"gentle speed stopped too early")
  error(90);precondition(player.rate==1)
  error(-600);precondition(player.rate==1,"correction direction incorrect")
  error(300);precondition(player.rate==1,"old direction retained")
  // Small drift must not turn into periodic hard seeks even after ten seconds.
  now=1_000;error(600)
  now=10_999;error(600);precondition(player.seekCount==0)
  now=11_000;error(600);precondition(player.seekCount==0 && engine.resyncCount==0)
  // Buffer recovery must preserve the same tolerance.
  now=12_000;error(600);player.buffering=true
  now=30_000;engine.tick();player.buffering=false
  now=31_000;error(600);precondition(player.seekCount==0)
  now=33_000;error(600);precondition(player.seekCount==0)
  now=43_000;error(600);precondition(player.seekCount==0)
  engine.receive(room("paused",2));engine.tick()
  precondition(!player.playing && player.rate==1)
  engine.receive(room("playing",3));player.duration=60_095;player.position=60_095;now=90_000
  let seeks=player.seekCount
  for _ in 0..<100 {engine.tick();now += 100}
  precondition(!player.playing && player.seekCount==seeks,"EOF caused repeated seek/play")
  precondition(engine.target()?.0==60_095 && engine.target()?.1=="paused")
  player.duration=0;precondition(engine.target()?.1=="playing","unknown duration clamped")
  player.playing=true;player.rate=1.05
  engine.resetSession()
  precondition(!player.playing && player.rate==1 && engine.room==nil && !clock.ready)
  clock.add(0,0,0,0);precondition(engine.tick()==nil && !player.playing,"old room resumed after reconnect")
  engine.receive(room("paused",1));engine.tick();precondition(!player.playing)
  // A normally improving correction must not be interrupted after ten seconds.
  engine.receive(room("playing",10));player.duration=3_900_000
  let beforeImproving=player.seekCount
  // Preserve a monotonic clock across reset / pause-to-play. The new
  // playback startup settling gate intentionally suppresses early seeks.
  let improvingStart=now+3000
  for i in 0...20 {now=improvingStart+Double(i)*1000;error(1450-Double(i)*50)}
  precondition(player.seekCount==beforeImproving,"improving drift caused unnecessary seek")
  now=improvingStart+21_000;error(600);now=improvingStart+31_000;error(600)
  precondition(player.seekCount==beforeImproving,"tolerated drift unexpectedly hard-seeked")
  precondition(!RecoveryBufferPolicy.ready(prepared:true,bufferedMs:3000,positionMs:10000,durationMs:100000,recovering:true))
  precondition(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:12000,positionMs:10000,durationMs:100000,recovering:true))
  precondition(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:1950,positionMs:98000,durationMs:100000,recovering:true),"tail cannot wait for twelve seconds")
  precondition(!RecoveryBufferPolicy.ready(prepared:false,bufferedMs:60000,positionMs:0,durationMs:100000,recovering:true))
  precondition(!RecoveryBufferPolicy.ready(prepared:true,bufferedMs:3000,positionMs:0,durationMs:0,recovering:true),"unknown duration bypassed reserve")
  precondition(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:1000,positionMs:0,durationMs:100000,recovering:false),"normal playing was interrupted")
  precondition(RecoveryBufferPolicy.ready(prepared:true,bufferedMs:3000,positionMs:10000,durationMs:100000,recovering:true,preparedFallback:true))
  precondition(!RecoveryBufferPolicy.ready(prepared:true,bufferedMs:1000,positionMs:10000,durationMs:100000,recovering:true,preparedFallback:true))
  engine.resetSession();clock.add(0,0,0,0);engine.receive(room());player.position=0;player.buffering=true;engine.tick();player.buffering=false
  let recoverySeeks=player.seekCount;engine.tick();precondition(player.seekCount==recoverySeeks && player.playing && player.rate==1)
  now += 1999;engine.tick();precondition(player.seekCount==recoverySeeks)
  now += 1;engine.tick()
  precondition(player.seekCount==recoverySeeks && player.playing,"first-frame startup must not be starved by hard seeks")
  for _ in 0..<10 {now += 3000;engine.tick()}
  precondition(player.seekCount==recoverySeeks,"no hard-seek storm before first movie frame")
  player.position=180;now += 100;engine.tick()
  precondition(player.seekCount==recoverySeeks,"automatic drift must use rate instead of hard seeks")
  // A ready AVPlayerItem may still be natively paused while recovering after
  // an HTTP interruption. Do not fire a hard seek every three seconds.
  engine.resetSession();clock.add(0,0,0,0);engine.receive(room())
  player.position=10_000+now;engine.tick()
  player.position=210_000
  player.nativePlaybackRunning=false
  let seekBeforePausedDecoder=player.seekCount
  for _ in 0..<10 {now += 4000;engine.tick()}
  precondition(player.seekCount==seekBeforePausedDecoder,"paused decoder must not enter a hard-seek storm")
  precondition(player.playing,"sync must keep requesting the decoder to resume")
  player.nativePlaybackRunning=true
  now += 4000;engine.tick()
  precondition(player.seekCount==seekBeforePausedDecoder,"native recovery must use catch-up speed without a hard seek")
  print("iOS SyncEngine regression checks passed")
 }
}
