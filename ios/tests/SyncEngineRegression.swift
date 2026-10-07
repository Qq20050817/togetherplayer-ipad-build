import Foundation

final class FakePlayer: PlayerAdapter {
 var position=0.0
 var duration=3_900_000.0
 var buffering=false
 var ready=true
 var rate: Float=1
 var seekCount=0
 var playing=false
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
  engine.receive(room())
  // Replay the observed boundary cycle: retain fast correction below 500ms.
  for value in [600.0,530,495,510,490,300] {
   now += 100;error(value);precondition(player.rate==1.05,"fast speed toggled near 500ms")
  }
  error(240);precondition(player.rate==1.02)
  error(180);precondition(player.rate==1.02,"gentle speed stopped too early")
  error(90);precondition(player.rate==1)
  error(-600);precondition(player.rate==0.95,"correction direction incorrect")
  error(300);precondition(player.rate==1.02,"old direction retained")
  // A decoder that makes no progress must receive a bounded resync.
  now=1_000;error(600)
  now=10_999;error(600);precondition(player.seekCount==0)
  now=11_000;error(600);precondition(player.seekCount==1 && engine.resyncCount==1)
  // Buffering must not consume the ten-second recovery budget.
  now=12_000;error(600);player.buffering=true
  now=30_000;engine.tick();player.buffering=false
  now=31_000;error(600);precondition(player.seekCount==1)
  now=33_000;error(600);precondition(player.seekCount==1)
  now=43_000;error(600);precondition(player.seekCount==2)
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
  for i in 0...20 {now=50_000+Double(i)*1000;error(1450-Double(i)*50)}
  precondition(player.seekCount==beforeImproving,"improving drift caused unnecessary seek")
  now=71_000;error(600);now=81_000;error(600)
  precondition(player.seekCount==beforeImproving+1,"stalled correction no longer resyncs")
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
  now += 1;engine.tick();precondition(player.seekCount==recoverySeeks+1)
  print("iOS SyncEngine regression checks passed")
 }
}
