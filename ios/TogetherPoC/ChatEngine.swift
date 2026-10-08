import Foundation
import Combine

struct ChatMessage: Codable, Identifiable {
 let id: Int64
 let userId: String
 let name: String
 let text: String
 let clientMessageId: String
 let timestamp: Double
}
struct RoomMember: Codable, Identifiable, Equatable {
 var id: String {userId}
 let userId: String
 let name: String
 let timelineOffset: Double
 let duration: Double
 let position: Double
 let ready: Bool
 let buffering: Bool
 let online: Bool
}
struct ReactionBubble: Identifiable {
 let id=UUID()
 let emoji: String
 let expiresAt: Double
}
@MainActor final class ChatEngine: ObservableObject {
 @Published private(set) var messages: [ChatMessage]=[]
 @Published private(set) var reactions: [ReactionBubble]=[]
 @Published private(set) var unread=0
 @Published private(set) var typingName=""
 @Published private(set) var danmaku: [DanmakuItem]=[]
 private var danmakuQueue=DanmakuQueue()
 var visible=true
 private var room=""
 private var typingUntil=0.0
 private var seen=Set<Int64>()
 func reset(_ id: String) {
  guard id != room else {return};room=id;messages=[];seen=[];reactions=[];unread=0;typingName="";danmakuQueue.reset();danmaku=[]
 }
 func accept(_ message: ChatMessage,mine: Bool,live: Bool=false,now: Double=0) {
  guard seen.insert(message.id).inserted else {return}
  messages.append(message);messages.sort {$0.id<$1.id}
  if messages.count>500 {messages.removeFirst(messages.count-500)}
  if !visible && !mine {unread += 1}
  if live {
   let voice=message.clientMessageId.hasPrefix("voice:")
   let speed=UserDefaults.standard.double(forKey:"danmakuSpeed")
   danmakuQueue.enqueue(id:message.id,text:"\(message.name)：\(message.text)",now:now,durationMs:DanmakuSpeed.duration(voice ? 5000 : 10000,speed:speed),characterLimit:voice ? 500 : 120)
   danmaku=danmakuQueue.active
  }
 }
 func markRead() {if unread != 0 {unread=0}}
 func reaction(_ emoji: String,now: Double) {reactions.append(ReactionBubble(emoji:emoji,expiresAt:now+4000));if reactions.count>12 {reactions.removeFirst(reactions.count-12)}}
 func typing(_ name: String,now: Double) {typingName=name;typingUntil=now+3000}
 func tick(_ now: Double) {
  if reactions.contains(where:{$0.expiresAt<=now}) {reactions.removeAll {$0.expiresAt<=now}}
  if !typingName.isEmpty && now>=typingUntil {typingName=""}
  danmakuQueue.advance(now);if danmaku != danmakuQueue.active {danmaku=danmakuQueue.active}
 }
}
