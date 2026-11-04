import Foundation
final class FakePlayer:PlayerAdapter {
 var position=10000.0;var duration=1000000.0;var ready=true;var buffering=false
 var rate:Float=1;var playing=false;var seeks=0
 func play(){playing=true};func pause(){playing=false};func seekTo(_ p:Double){position=p;seeks+=1};func setPlaybackSpeed(_ r:Float){rate=r}
}
@main struct SyncEngineRegression {
 static func main(){
  var now=0.0;let c=ClockSync{now};c.add(0,0,0,0);let p=FakePlayer();let e=SyncEngine(p,c)
  func room(_ pos:Double=10000,_ version:Int64=1)->Room {Room(roomId:"r",hostId:"h",mediaUrl:"https://example.org/movie.mp4",version:version,executeAt:0,state:"playing",position:pos,updatedAt:0,playbackRate:1,before:Timeline(state:"playing",position:10000,updatedAt:0,playbackRate:1))}
  e.receive(room());e.tick()
  for gap in [-3000.0,-1000,0,1000,3000]{p.position=10000-gap;e.tick();precondition(p.rate==1 && p.seeks==0)}
  for gap in [4000.0,5000] {p.position=10000-gap;e.tick();precondition(p.rate==1 && p.playing && p.seeks==0)}
  for t in 0...50 {now=Double(t)*100;p.position=10000+now-6000;e.tick();if t<50 {precondition(p.rate==1)}}
  precondition(p.rate>1 && p.seeks==0)
  p.position=10000+now-3000;e.tick();precondition(p.rate==1)
  now=0
  e.receive(room(12000,2));e.tick();precondition(p.position==12000 && p.seeks==1)
  for _ in 0..<100{e.tick()};precondition(p.seeks==1)
  e.resetSession();now=20000;precondition(!p.playing && e.tick()==nil)
  print("Three-second tolerance, speed catchup, explicit small seek and reset passed")
 }
}
