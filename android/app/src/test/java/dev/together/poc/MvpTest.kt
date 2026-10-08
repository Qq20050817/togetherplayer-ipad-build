package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject
class MvpTest {
 @Test fun offsetAppliesOnceAndClampsNegativeStart(){
  val clock=ClockSync {1000.0};clock.add(0.0,0.0,0.0,0.0);val p=SyncCoreTest.FakePlayer();val e=SyncEngine(p,clock)
  e.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"paused","position":5000,"updatedAt":0,"playbackRate":1,"before":{}}"""));e.timelineOffset=8000.0;e.tick();assertEquals(13000L,p.pos);repeat(5){e.tick()};assertEquals(13000L,p.pos)
  e.timelineOffset=-8000.0;e.tick();assertEquals(0L,p.pos)
 }
 @Test fun chatDedupUnreadAndRoomIsolation(){val c=ChatEngine();c.reset("r");c.visible=false;val m=ChatMessage(1,"u","好友","你好","id");assertTrue(c.accept(m,false));assertFalse(c.accept(m,false));assertEquals(1,c.unread);c.typing("好友",1000.0);c.tick(4001.0);assertEquals("",c.typingName);c.reset("next");assertTrue(c.messages.isEmpty());assertEquals(0,c.unread)}
 @Test fun mediaSourcePrivacyAndWebdavNormalization(){assertEquals("https://example.com/movie.mp4",MediaSources.resolve("webdavs://example.com/movie.mp4"));assertFalse(MediaSources.canShare("https://example.com/movie?access_token=secret"));assertFalse(MediaSources.canShare("https://user:pass@example.com/movie"));assertFalse(MediaSources.canShare("file:///movie"));assertTrue(MediaSources.canShare("https://example.com/movie.m3u8"))}
}
