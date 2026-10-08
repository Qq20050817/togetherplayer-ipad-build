package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject

class SyncCoreTest {
 class FakePlayer : PlayerAdapter {
  var pos=0L;var rate=1f;var playing=false;var seeks=0;var ready=true;var acceptSeek=true;var durationMs=4000000L;var buffering=false
  override fun play() {playing=true};override fun pause() {playing=false}
  override fun seekTo(positionMs:Long) {if(acceptSeek) pos=positionMs;seeks++}
  override fun getPosition()=pos;override fun getDuration()=durationMs
  override fun isBuffering()=buffering;override fun isReady()=ready
  override fun setPlaybackSpeed(speed:Float){rate=speed}
 }
 @Test fun finiteMovieEndDoesNotTriggerRepeatedOutOfRangeSeeks() {
  var now=90000.0;val clock=ClockSync {now};clock.add(0.0,0.0,0.0,0.0)
  val player=FakePlayer();player.durationMs=60095;player.pos=60095;player.playing=true
  val engine=SyncEngine(player,clock)
  engine.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"playing","position":0,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  repeat(100) {engine.tick();now+=100}
  assertFalse(player.playing);assertEquals(0,player.seeks)
  assertEquals(60095.0,engine.target()!!.first,0.001);assertEquals("paused",engine.target()!!.second)
  // An actual Seek back into the movie must resume; no sticky end flag.
  engine.receive(JSONObject(engine.room.toString()).put("version",2).put("position",0).put("updatedAt",now));player.pos=0;engine.tick()
  assertTrue(player.playing)
  player.durationMs=-9223372036854775807L
  now+=100000;assertEquals("playing",engine.target()!!.second)
 }
 @Test fun ntpUsesMonotonicTimeAndBestSample() {
  val clock=ClockSync {2000.0}
  clock.add(1000.0,1001010.0,1001012.0,1022.0)
  assertEquals(1000000.0,clock.offset,0.001)
  assertEquals(1002000.0,clock.serverNow(),0.001)
  clock.add(1000.0,1001050.0,1001052.0,1062.0)
  assertEquals(1000000.0,clock.offset,0.001)
  clock.reset();assertFalse(clock.ready)
 }
 @Test fun futurePauseAndOlderVersionCannotPauseEarly() {
  var time=1000.0;val clock=ClockSync {time};clock.add(0.0,0.0,0.0,0.0)
  val player=FakePlayer();val engine=SyncEngine(player,clock)
  val room=JSONObject("""{"version":2,"executeAt":2000,"state":"paused","position":2000,"updatedAt":2000,"playbackRate":1,"before":{"state":"playing","position":0,"updatedAt":0,"playbackRate":1}}""")
  engine.receive(room);player.pos=1000;engine.tick();assertTrue(player.playing)
  engine.receive(JSONObject(room.toString()).put("version",1).put("executeAt",0))
  assertEquals(2L,engine.version)
  time=2000.0;player.pos=2000;engine.tick();assertFalse(player.playing)
 }
 @Test fun driftUsesSpeedAndSevereErrorSeeksOnceThenRestoresSpeed() {
  val clock=ClockSync {1000.0};clock.add(0.0,0.0,0.0,0.0)
  val player=FakePlayer();val engine=SyncEngine(player,clock)
  engine.receive(JSONObject("""{"version":1,"executeAt":0,"state":"playing","position":0,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  player.pos=700;engine.tick();assertEquals(1.02f,player.rate,0.0001f);assertEquals(0,player.seeks)
  player.pos=0;engine.tick();assertEquals(1.05f,player.rate,0.0001f)
  player.pos=5000;engine.tick();assertEquals(1000L,player.pos);assertEquals(1,player.seeks)
  engine.tick();assertEquals(1f,player.rate,0.0001f);assertEquals(1,player.seeks)
 }
 @Test fun versionIsScopedToRoom() {
  val engine=SyncEngine(FakePlayer(),ClockSync {0.0})
  engine.receive(JSONObject().put("roomId","a").put("version",200))
  engine.receive(JSONObject().put("roomId","b").put("version",1))
  assertEquals(1L,engine.version)
  engine.receive(JSONObject().put("roomId","b").put("version",0))
  assertEquals(1L,engine.version)
 }
 @Test fun returnFromBackgroundCannotPlayStaleRoomBeforeFreshSnapshotAndClock() {
  var time=1000.0;val clock=ClockSync {time};clock.add(0.0,0.0,0.0,0.0)
  val player=FakePlayer();val engine=SyncEngine(player,clock)
  val playing=JSONObject("""{"roomId":"r","version":2,"executeAt":0,"state":"playing","position":0,"updatedAt":0,"playbackRate":1,"before":{}}""")
  engine.receive(playing);player.pos=1000;engine.tick();assertTrue(player.playing)
  engine.resetSession();time=20000.0
  assertFalse(player.playing);assertNull(engine.tick());assertNull(engine.room)
  // Even a new clock sample cannot reactivate the previous playing snapshot.
  clock.add(0.0,0.0,0.0,0.0);assertNull(engine.tick());assertFalse(player.playing)
  val paused=JSONObject(playing.toString()).put("version",3).put("state","paused").put("position",1300)
  engine.receive(paused);engine.tick();assertFalse(player.playing);assertEquals(1300L,player.pos)
  repeat(10){time+=1000;engine.tick()};assertFalse(player.playing);assertEquals(1300L,player.pos)
 }
 @Test fun pauseCancelsPlayIntentEvenWhilePlayerNotReady() {
  val clock=ClockSync {1000.0};clock.add(0.0,0.0,0.0,0.0)
  val player=FakePlayer();player.playing=true;player.ready=false
  val engine=SyncEngine(player,clock)
  engine.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  engine.tick();assertFalse(player.playing);assertEquals(0,player.seeks)
 }

 @Test fun improvingDriftIsNotInterruptedByTenSecondSeek() {
  var now=0.0;val clock=ClockSync {now};clock.add(0.0,0.0,0.0,0.0)
  val p=FakePlayer();val e=SyncEngine(p,clock)
  e.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"playing","position":10000,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  for(i in 0..20) {now=i*1000.0;p.pos=(10000+now-(1450-i*50)).toLong();e.tick()}
  assertEquals(0,p.seeks)
  now=21000.0;p.pos=(10000+now-600).toLong();e.tick()
  now=31000.0;p.pos=(10000+now-600).toLong();e.tick();assertEquals(1,p.seeks)
 }
 @Test fun correctionHysteresisPreventsBoundarySpeedFlapping() {
  val clock=ClockSync {10000.0};clock.add(0.0,0.0,0.0,0.0);val p=FakePlayer();val e=SyncEngine(p,clock)
  e.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"playing","position":0,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  for(error in listOf(600,490,510,490,300)) {p.pos=10000L-error;e.tick();assertEquals(1.05f,p.rate,0.0001f)}
  p.pos=9760;e.tick();assertEquals(1.02f,p.rate,0.0001f)
  p.pos=9820;e.tick();assertEquals(1.02f,p.rate,0.0001f)
  p.pos=9910;e.tick();assertEquals(1f,p.rate,0.0001f)
 }
 @Test fun recoveryDoesNotImmediatelySeekBackIntoBuffering() {
  var now=1000.0;val clock=ClockSync {now};clock.add(0.0,0.0,0.0,0.0);val p=FakePlayer();val e=SyncEngine(p,clock)
  e.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"playing","position":10000,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  p.buffering=true;e.tick();p.buffering=false
  e.tick();assertEquals(0,p.seeks);assertTrue(p.playing);assertEquals(1f,p.rate,0.001f)
  now=2999.0;e.tick();assertEquals(0,p.seeks)
  now=3000.0;e.tick();assertEquals(1,p.seeks)
 }
 @Test fun slowSeekCompletionCannotCauseTenSeeksPerSecond() {
  var now=1000.0;val clock=ClockSync {now};clock.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.acceptSeek=false;val e=SyncEngine(p,clock)
  val room=JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"playing","position":10000,"updatedAt":0,"playbackRate":1,"before":{}}""")
  e.receive(room);e.tick();assertEquals(1,p.seeks)
  repeat(29) {now+=100;e.tick()};assertEquals(1,p.seeks)
  now=4000.0;e.tick();assertEquals(2,p.seeks)
  e.receive(JSONObject(room.toString()).put("version",2));e.tick();assertEquals(3,p.seeks)
 }

}
