import Foundation
import Combine
@main struct ChatRefreshRegression {
 @MainActor static func main() {
  let chat=ChatEngine();var notifications=0
  let subscription=chat.objectWillChange.sink {_ in notifications += 1}
  for t in 0..<600 {chat.tick(Double(t)*100)}
  chat.markRead();precondition(notifications==0,"idle ticks must not rebuild UI")
  chat.typing("好友",now:60000);let typingStart=notifications
  for t in 0..<29 {chat.tick(60000+Double(t)*100)}
  precondition(notifications==typingStart && chat.typingName=="好友")
  chat.tick(63000);precondition(chat.typingName.isEmpty && notifications==typingStart+1)
  let afterTyping=notifications;for t in 0..<60 {chat.tick(64000+Double(t)*100)}
  precondition(notifications==afterTyping,"expired typing must clear once")
  chat.reaction("❤️",now:70000);let reactionStart=notifications
  chat.tick(73999);precondition(chat.reactions.count==1 && notifications==reactionStart)
  chat.tick(74000);precondition(chat.reactions.isEmpty && notifications==reactionStart+1)
  chat.tick(75000);precondition(notifications==reactionStart+1)
  chat.accept(ChatMessage(id:1,userId:"peer",name:"好友",text:"测试弹幕",clientMessageId:"fixture",timestamp:80000),mine:false,live:true,now:80000)
  precondition(chat.danmaku.count==1);chat.tick(90000);precondition(chat.danmaku.isEmpty)
  withExtendedLifetime(subscription) {}
  print("PASS: 600 idle ticks publish zero UI updates; typing/reaction expiry publishes once; live danmaku expiry preserved")
 }
}
