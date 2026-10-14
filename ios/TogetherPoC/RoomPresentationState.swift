import Foundation
import Combine

// Transport snapshots may change position/clock every second without changing
// anything the surrounding page displays. Keep those updates in the roster.
@MainActor final class RoomRosterState: ObservableObject {
 @Published private(set) var members:[RoomMember]=[]
 func update(_ next:[RoomMember]) {
  if members != next {members=next}
 }
 static func samePresentation(_ lhs:[RoomMember],_ rhs:[RoomMember])->Bool {
  guard lhs.count==rhs.count else{return false}
  return zip(lhs,rhs).allSatisfy {a,b in
   a.userId==b.userId && a.name==b.name && a.timelineOffset==b.timelineOffset &&
   a.duration==b.duration && a.ready==b.ready && a.buffering==b.buffering && a.online==b.online
  }
 }
}

struct RoomPresentationState:Equatable {
 let roomID:String
 let hostID:String
 let mediaURL:String
 let version:Int64
 let state:String
 let rate:Double
 let title:String?
 let duration:Double?
 let waiting:Bool?
 let pauseReason:String?
 let autoResume:Bool?
 init(_ room:Room) {
  roomID=room.roomId;hostID=room.hostId;mediaURL=room.mediaUrl;version=room.version
  state=room.state;rate=room.playbackRate;title=room.title;duration=room.duration
  waiting=room.waitForPeer;pauseReason=room.pauseReason;autoResume=room.autoResume
 }
}

enum PlotPollPresentation {
 static func same(_ lhs:[String:Any]?,_ rhs:[String:Any]?)->Bool {
  switch (lhs,rhs) {
  case (nil,nil):return true
  case (let lhs?,let rhs?):return NSDictionary(dictionary:lhs).isEqual(to:rhs)
  default:return false
  }
 }
}
