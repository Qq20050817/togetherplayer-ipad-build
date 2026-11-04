import Foundation

enum RoomEnvelope {
 static func decode(_ data: Data) -> [String:Any]? {
  // Reconnect WELCOME frames can include room state and a large chat backlog.
   // Keep a bounded limit without dropping otherwise valid snapshots above 8 KiB.
   guard !data.isEmpty,data.count<=1_048_576,
   let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
   let type=value["type"] as? String,!type.isEmpty else {return nil}
  return value
 }
}

enum RoomConnectionHealth {
 static func timeout(now: Double,connected: Bool,startedAt: Double,lastMessageAt: Double,inFlightAt: Double?) -> String? {
  if !connected,now-startedAt>20000 {return "welcome_timeout"}
  if connected,now-lastMessageAt>25000 {return "message_timeout"}
  if connected,let sentAt=inFlightAt,now-sentAt>12000 {return "ack_timeout"}
  return nil
 }
}

struct PendingRoomMedia {
 let roomID: String
 let url: String
 let title: String
 var operation: [String:Any] {["type":"ROOM_MEDIA","data":["mediaUrl":url,"title":title]]}
 func matches(_ room: Room) -> Bool {room.roomId==roomID && room.mediaUrl==url && (room.title ?? "")==title}
}

enum RoomResumePolicy {
 static func shouldReconnect(hasCredentials: Bool,wasForeground: Bool,isConnected: Bool,hasSocket: Bool,lastMessageAgeMs: Double,connectionAgeMs: Double) -> Bool {
  guard hasCredentials else {return false}
  if !wasForeground || !hasSocket {return true}
  // A resumed inactive scene may hold a stale socket even while still marked connected.
  // Avoid disrupting a genuinely healthy socket or a handshake still in progress.
  return isConnected ? lastMessageAgeMs >= 15_000 : connectionAgeMs >= 10_000
 }
}
