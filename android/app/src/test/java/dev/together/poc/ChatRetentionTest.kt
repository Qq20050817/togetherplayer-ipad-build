package dev.together.poc

import org.junit.Test
import org.junit.Assert.*

class ChatRetentionTest {
 private fun message(id:Long)=ChatMessage(id,"peer","好友","消息","m-$id")
 @Test fun evictedReplayDoesNotBecomeUnreadAndResetAllowsNewRoomHistory(){
  val chat=ChatEngine();chat.reset("room");chat.visible=false
  for(id in 1L..700L)assertTrue(chat.accept(message(id),false))
  assertEquals(500,chat.messages.size);assertEquals(201L,chat.messages.first().id)
  chat.read();assertFalse(chat.accept(message(1),false));assertFalse(chat.accept(message(700),false))
  assertEquals(0,chat.unread);assertEquals(500,chat.messages.size)
  chat.reset("other-room");assertTrue(chat.accept(message(1),false));assertEquals(1,chat.unread)
 }
 @Test fun outOfOrderMessagesAreSortedAndSameRoomResetPreservesHistory(){
  val chat=ChatEngine();chat.reset("room")
  for(id in listOf(3L,1L,2L,2L))chat.accept(message(id),false)
  assertEquals(listOf(1L,2L,3L),chat.messages.map {it.id})
  chat.reset("room");assertEquals(3,chat.messages.size)
 }
 @Test fun unseenMessageOlderThanFullWindowDoesNotTriggerUnread(){
  val chat=ChatEngine();chat.reset("room");chat.visible=false
  for(id in 1001L..1500L)chat.accept(message(id),false)
  chat.read();assertFalse(chat.accept(message(1),false));assertEquals(0,chat.unread)
  assertEquals(1001L,chat.messages.first().id)
 }
}
