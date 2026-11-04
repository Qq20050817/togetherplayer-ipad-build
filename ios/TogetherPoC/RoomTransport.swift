import Foundation
import Security

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
   case NSURLErrorSecureConnectionFailed:
    let underlying=(error.userInfo[NSUnderlyingErrorKey] as? NSError).map {"，底层错误 \($0.code)"} ?? ""
    return "安全握手失败（\(error.code)\(underlying)）"
   case NSURLErrorServerCertificateUntrusted:return "服务器证书不受信任（\(error.code)）"
   case NSURLErrorServerCertificateHasBadDate,NSURLErrorServerCertificateNotYetValid:return "服务器证书日期异常（\(error.code)）"
   default:return "网络错误 \(error.code)"
   }
  }
  return "连接错误 \(error.code)"
 }
}

/// A single TLS 1.2 retry for generic handshake failures. Trust validation stays
/// with URLSession; certificate errors and application HTTP errors never qualify.
struct RoomTLSCompatibility {
 private(set) var usesTLS12=false
 mutating func reset() {usesTLS12=false}
 mutating func retryAfterHandshakeFailure(_ error:NSError,httpStatus:Int?) -> Bool {
  guard !usesTLS12,error.domain==NSURLErrorDomain,error.code==NSURLErrorSecureConnectionFailed,
   httpStatus==nil || httpStatus==101 else {return false}
  usesTLS12=true
  return true
 }
 func configuration() -> URLSessionConfiguration {
  let configuration=URLSessionConfiguration.ephemeral
  configuration.waitsForConnectivity=false
  configuration.timeoutIntervalForRequest=15
  configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
  if usesTLS12 {configuration.tlsMaximumSupportedProtocolVersion = .TLSv12}
  return configuration
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
  // iPad multiwindow and app switching may go inactive without entering background.
  // Reopen the transport after a meaningful inactive interval to avoid a half-open socket.
  if inactiveDurationMs >= 3000 {return true}
  // A resumed inactive scene may hold a stale socket even while still marked connected.
  // Avoid disrupting a genuinely healthy socket or a handshake still in progress.
  return isConnected ? lastMessageAgeMs >= 15_000 : connectionAgeMs >= 10_000
 }
}
