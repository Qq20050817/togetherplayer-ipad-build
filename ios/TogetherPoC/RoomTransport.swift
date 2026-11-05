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
 static func operationExpired(now:Double,sentAt:Double?)->Bool {
  guard let sentAt else{return false}
  return now-sentAt>12000
 }
 static func timeout(now: Double,connected: Bool,startedAt: Double,lastMessageAt: Double,inFlightAt: Double?) -> String? {
  if !connected,now-startedAt>20000 {return "welcome_timeout"}
  if connected,now-lastMessageAt>25000 {return "message_timeout"}
  return nil
 }
}

enum RoomTransportFailure {
 static func description(_ error: NSError, httpStatus: Int?) -> String {
  if let httpStatus,httpStatus != 101 {
   if httpStatus == 401 {return "房间凭证失效（HTTP 401）"}
   if httpStatus == 403 {return "服务器拒绝连接（HTTP 403）"}
   if [502,503,504].contains(httpStatus) {return "服务器入口暂不可用（HTTP \(httpStatus)）"}
   return "服务器响应 HTTP \(httpStatus)"
  }
  if error.domain == NSURLErrorDomain {
   switch error.code {
   case NSURLErrorTimedOut:return "连接超时"
   case NSURLErrorNotConnectedToInternet:return "当前网络不可用"
   case NSURLErrorNetworkConnectionLost:return "网络连接中断"
   case NSURLErrorCannotFindHost,NSURLErrorDNSLookupFailed:return "无法解析服务器地址"
   case NSURLErrorCannotConnectToHost:return "无法连接服务器"
   case NSURLErrorSecureConnectionFailed:return "安全握手失败（\(error.code)）"
   case NSURLErrorServerCertificateUntrusted:return "服务器证书不受信任（\(error.code)）"
   default:return "网络错误 \(error.code)"
   }
  }
  return "连接错误 \(error.code)"
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
 static func shouldReconnect(hasCredentials: Bool,wasForeground: Bool,isConnected: Bool,hasSocket: Bool,lastMessageAgeMs: Double,connectionAgeMs: Double,inactiveDurationMs: Double=0) -> Bool {
  guard hasCredentials else {return false}
  if !wasForeground || !hasSocket {return true}
  // An inactive scene can keep receiving healthy room messages. Use actual
  // transport freshness rather than the duration of an overlay or split view.
  // A resumed inactive scene may hold a stale socket even while still marked connected.
  // Avoid disrupting a genuinely healthy socket or a handshake still in progress.
  return isConnected ? lastMessageAgeMs >= 15_000 : connectionAgeMs >= 10_000
 }
}

/// A single bounded foreground outage; retries cannot renew its deadline.
struct RoomReconnectContinuity {
 private(set) var roomID:String?
 private(set) var mediaURL:String?
 private(set) var deadline:Double?
 mutating func begin(roomID:String,mediaURL:String,now:Double,canContinue:Bool)->Bool {
  if deadline != nil {return preserves(roomID:roomID,mediaURL:mediaURL,now:now) && canContinue}
  guard canContinue,now.isFinite,!roomID.isEmpty,!mediaURL.isEmpty else{return false}
  self.roomID=roomID;self.mediaURL=mediaURL;deadline=now+8000
  return true
 }
 func preserves(roomID:String,mediaURL:String,now:Double)->Bool {
  guard let deadline,now.isFinite else{return false}
  return self.roomID==roomID && self.mediaURL==mediaURL && now<deadline
 }
 mutating func reset(){roomID=nil;mediaURL=nil;deadline=nil}
}
