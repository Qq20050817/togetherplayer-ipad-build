import Foundation

@main struct P2PMuseHandoffRegression {
 static func main() {
  var guardState=P2PMuseHandoff()
  func check(_ now:Double,_ version:Int64=10,_ state:String="paused",
             _ position:Double=10_000,_ executeAt:Double=0,_ serverNow:Double=0,
             room:String="room",media:String="movie",blocked:Bool=false)->Bool {
   guardState.shouldDefer(now:now,roomID:room,mediaURL:media,version:version,
                          state:state,positionMs:position,executeAtMs:executeAt,
                          serverNowMs:serverNow,blocked:blocked)
  }
  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.play,positionMs:10_000,now:100)
  precondition(check(200),"a delayed Muse ACK must not replay the old PAUSE")
  precondition(check(300,11,"playing",10_000,900,400),"new PLAY is still scheduled")
  precondition(!check(800,11,"playing",10_000,900,900),"resume Muse at executeAt")
  precondition(!check(801),"acknowledged preview should be cleared")

  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.play,positionMs:10_000,now:100)
  precondition(!check(200,11,"paused",10_000,900,400),"rejected PLAY falls back immediately")
  precondition(!check(210),"rejection must clear the fast hint")

  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.play,positionMs:10_000,now:100)
  precondition(check(2599),"a pending preview may be held briefly")
  precondition(!check(2601),"Muse timeout is always bounded")

  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.seek,positionMs:70_000,now:100)
  precondition(check(200,11,"playing",70_200,950,300),"confirmed SEEK waits until executeAt")
  precondition(!check(300,11,"playing",70_200,950,950))

  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.seek,positionMs:70_000,now:100)
  precondition(!check(200,11,"playing",12_000,950,300),"different seek position is not confirmation")

  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.pause,positionMs:10_000,now:100)
  precondition(check(150,11,"paused",10_000,950,300),"PAUSE remains held during scheduled transition")
  precondition(!check(190,12,"paused",10_000,950,300),"newer room commands must win")

  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.pause,positionMs:10_000,now:100)
  precondition(!check(150,10,"paused",10_000,0,0,room:"other"),"room switch cancels hint")
  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.pause,positionMs:10_000,now:100)
  precondition(!check(150,10,"paused",10_000,0,0,media:"other"),"media switch cancels hint")
  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.pause,positionMs:10_000,now:100)
  precondition(!check(150,10,"paused",10_000,0,0,blocked:true),"AI question pauses win")
  guardState.begin(roomID:"room",mediaURL:"movie",version:10,action:.pause,positionMs:10_000,now:100)
  guardState.reset()
  precondition(!check(150),"disconnect and reset must restore Muse")

  print("P2P to Muse handoff regression checks passed")
 }
}
