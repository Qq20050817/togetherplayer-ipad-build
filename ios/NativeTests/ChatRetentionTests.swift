import XCTest
@testable import TogetherPoC

@MainActor final class ChatRetentionTests:XCTestCase {
 private func message(_ id:Int64)->ChatMessage {
  ChatMessage(id:id,userId:"peer",name:"好友",text:"消息",clientMessageId:"m-\(id)",timestamp:0)
 }
 func testEvictedReplayDoesNotBecomeUnreadOrLiveDanmaku() {
  let chat=ChatEngine();chat.reset("room");chat.visible=false
  for id in 1...700 {chat.accept(message(Int64(id)),mine:false)}
  XCTAssertEqual(chat.messages.count,500);XCTAssertEqual(chat.messages.first?.id,201)
  chat.markRead()
  chat.accept(message(1),mine:false,live:true,now:1000)
  chat.accept(message(700),mine:false,live:true,now:1000)
  XCTAssertEqual(chat.unread,0);XCTAssertTrue(chat.danmaku.isEmpty)
  XCTAssertEqual(chat.messages.count,500)
  chat.reset("other-room");chat.accept(message(1),mine:false)
  XCTAssertEqual(chat.messages.map(\.id),[1]);XCTAssertEqual(chat.unread,1)
 }
 func testOutOfOrderMessagesAreRetainedInOrderInsideHistoryWindow() {
  let chat=ChatEngine();chat.reset("room")
  for id in [Int64(3),1,2,2] {chat.accept(message(id),mine:false)}
  XCTAssertEqual(chat.messages.map(\.id),[1,2,3])
  chat.reset("room");XCTAssertEqual(chat.messages.count,3)
 }
 func testUnseenMessageOlderThanFullWindowCannotTriggerUnread() {
  let chat=ChatEngine();chat.visible=false;chat.reset("room")
  for id in 1001...1500 {chat.accept(message(Int64(id)),mine:false)}
  chat.markRead();chat.accept(message(1),mine:false,live:true,now:0)
  XCTAssertEqual(chat.unread,0);XCTAssertTrue(chat.danmaku.isEmpty)
  XCTAssertEqual(chat.messages.first?.id,1001)
 }
}
