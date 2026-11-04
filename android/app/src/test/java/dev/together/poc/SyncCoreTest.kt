package dev.together.poc
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject

class SyncCoreTest {
 class FakePlayer : PlayerAdapter {
  var pos=0L;var rate=1f;var playing=false;var seeks=0;var ready=true;var acceptSeek=true;var durationMs=4000000L;var buffering=false;var reserve=Long.MAX_VALUE;var advancing=true
  override fun play() {playing=true};override fun pause() {playing=false}
  override fun seekTo(positionMs:Long) {if(acceptSeek) pos=positionMs;seeks++}
  override fun getPosition()=pos;override fun getDuration()=durationMs
  override fun isAdvancing()=advancing;override fun getBufferedAhead()=reserve
  override fun isBuffering()=buffering;override fun isReady()=ready
  override fun setPlaybackSpeed(speed:Float){rate=speed}
 }
 private fun frame(position:Double=10000.0,version:Long=1,at:Double=0.0)=JSONObject().put("roomId","r").put("mediaUrl","https://example.org/movie.mp4").put("version",version).put("executeAt",at).put("state","playing").put("position",position).put("updatedAt",at).put("playbackRate",1).put("before",JSONObject().put("state","playing").put("position",10000).put("updatedAt",0).put("playbackRate",1))
 @Test fun leadingWaitHasStrictEntryAndResumesWhileNativeIsPaused(){
  var now=0.0;val c=ClockSync{now};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c);e.receive(frame());e.tick()
  p.pos=20000;e.tick();assertFalse(e.isSyncWaiting);assertTrue(p.playing)
  p.pos=20001;e.tick();assertTrue(e.isSyncWaiting);assertFalse(p.playing)
  p.advancing=false;now=9000.0;e.tick();assertTrue(e.isSyncWaiting);assertFalse(p.playing)
  now=9001.0;e.tick();assertFalse(e.isSyncWaiting);assertTrue(p.playing);assertEquals(0,p.seeks)
 }
 @Test fun explicitSeekAndPauseOverrideLeadingWait(){
  val c=ClockSync{0.0};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c);e.receive(frame());e.tick()
  p.pos=30000;e.tick();assertTrue(e.isSyncWaiting)
  e.receive(frame(12000.0,2));e.tick();assertFalse(e.isSyncWaiting);assertTrue(p.playing);assertEquals(12000L,p.pos);assertEquals(1,p.seeks)
  p.pos=40000;e.tick();assertTrue(e.isSyncWaiting)
  e.receive(frame(12000.0,3).put("state","paused"));e.tick();assertFalse(e.isSyncWaiting);assertFalse(p.playing)
 }
 @Test fun waitingHonorsOffsetAndSessionReset(){
  val c=ClockSync{0.0};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();val e=SyncEngine(p,c);e.timelineOffset=5000.0;p.pos=15000;e.receive(frame());e.tick()
  p.pos=25000;e.tick();assertFalse(e.isSyncWaiting)
  p.pos=25001;e.tick();assertTrue(e.isSyncWaiting)
  e.resetSession();assertFalse(e.isSyncWaiting);assertNull(e.room)
 }
 @Test fun bufferingClearsIntentionalWaiting(){
  val c=ClockSync{0.0};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c);e.receive(frame());e.tick()
  p.pos=30000;e.tick();assertTrue(e.isSyncWaiting)
  p.buffering=true;e.tick();assertFalse(e.isSyncWaiting)
 }
 @Test fun catchupNeedsAdvancingFramesAndBufferReserve(){
  val c=ClockSync{0.0};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c);e.receive(frame());e.tick()
  p.pos=5000;p.reserve=1000;e.tick();assertEquals(1f,p.rate)
  p.reserve=10000;p.advancing=false;e.tick();assertEquals(1f,p.rate)
  p.advancing=true;e.tick();assertTrue(p.rate>1f);assertEquals(0,p.seeks)
 }
 @Test fun rateTransitionSettlesWithoutAutomaticHardSeek() {
  var now=0.0;val c=ClockSync{now};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c)
  e.receive(frame());e.tick();now=100.0
  e.receive(frame(10100.0,2,100.0).put("playbackRate",2))
  now=300.0;e.tick();assertEquals(2f,p.rate);assertEquals(0,p.seeks)
  now=3000.0;e.tick();assertEquals(0,p.seeks);assertTrue(p.rate>=2f)
 }
 @Test fun bufferingPreservesRequestedPlayback() {
  val clock=ClockSync {0.0};clock.add(0.0,0.0,0.0,0.0)
  val p=FakePlayer();p.buffering=true;p.ready=false;val engine=SyncEngine(p,clock)
  engine.receive(JSONObject("""{"roomId":"r","version":1,"executeAt":0,"state":"playing","position":0,"updatedAt":0,"playbackRate":1,"before":{}}"""))
  engine.tick();assertTrue(p.playing)
 }
 @Test fun stalledPlaybackWakesRebuildsAndPauseDisarms() {
  val watcher=PlaybackRecovery()
  assertEquals(PlaybackRecovery.Action.NONE,watcher.observe(0.0,1000,true))
  assertEquals(PlaybackRecovery.Action.NONE,watcher.observe(4999.0,1000,true))
  assertEquals(PlaybackRecovery.Action.WAKE,watcher.observe(5000.0,1000,true))
  assertEquals(PlaybackRecovery.Action.REBUILD,watcher.observe(14000.0,1000,true))
  assertEquals(PlaybackRecovery.Action.NONE,watcher.observe(16000.0,1000,false))
  assertEquals(PlaybackRecovery.Action.NONE,watcher.observe(17000.0,1000,true))
 }
 @Test fun roomDoubleSpeedAppliesOnlyAtSharedExecutionTimeAndRestores() {
  var now=1000.0;val clock=ClockSync {now};clock.add(0.0,0.0,0.0,0.0)
  val player=FakePlayer();val engine=SyncEngine(player,clock)
  engine.receive(JSONObject("""{"roomId":"r","version":2,"executeAt":1150,"state":"playing","position":1150,"updatedAt":1150,"playbackRate":2,"before":{"state":"playing","position":1000,"updatedAt":1000,"playbackRate":1}}"""))
  player.pos=1000;engine.tick();assertEquals(1f,player.rate)
  now=1250.0;player.pos=1350;engine.tick();assertEquals(2f,player.rate)
  engine.receive(JSONObject(engine.room.toString()).put("version",3).put("executeAt",now).put("position",1350).put("updatedAt",now).put("playbackRate",1));engine.tick();assertEquals(1f,player.rate)
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
 @Test fun threeSecondToleranceAndCatchupWithoutSeek() {
  val c=ClockSync{0.0};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c)
  e.receive(frame());e.tick()
  for(gap in listOf(-3000L,-1000L,0L,1000L,3000L)){p.pos=10000-gap;e.tick();assertEquals(1f,p.rate);assertEquals(0,p.seeks)}
  p.pos=6000;e.tick();assertTrue(p.rate>1f);assertEquals(0,p.seeks)
  p.pos=9500;e.tick();assertEquals(1f,p.rate)
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

 @Test fun longRunningCatchupCannotLoopThroughHardSeeks() {
  var now=0.0;val c=ClockSync{now};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c)
  e.receive(frame());e.tick()
  repeat(120){now+=1000;p.pos=(10000+now-10000).toLong();e.tick();assertEquals(0,p.seeks)}
 }
 @Test fun smallExplicitSeekBypassesToleranceAndIgnoresStaleSnapshot() {
  var now=0.0;val c=ClockSync{now};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c)
  e.receive(frame());e.tick();e.receive(frame(12000.0,2,750.0))
  now=500.0;e.tick();assertEquals(0,p.seeks)
  now=750.0;e.tick();assertEquals(1,p.seeks);assertEquals(12000L,p.pos)
  e.receive(frame(12000.0,2,750.0));e.tick();e.receive(frame());e.tick();assertEquals(1,p.seeks)
 }
 @Test fun loadingRetainsLatestExplicitSeekAndTimelineOffset() {
  val c=ClockSync{0.0};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c)
  e.receive(frame());e.tick();p.ready=false;e.timelineOffset=500.0
  e.receive(frame(20000.0,2));e.tick();e.receive(frame(80000.0,3));e.tick();assertEquals(0,p.seeks)
  p.ready=true;e.tick();assertEquals(1,p.seeks);assertEquals(80500L,p.pos)
 }
 @Test fun slowExplicitSeekIsIssuedOncePerNewRoomVersion() {
  var now=0.0;val c=ClockSync{now};c.add(0.0,0.0,0.0,0.0);val p=FakePlayer();p.pos=10000;val e=SyncEngine(p,c)
  e.receive(frame());e.tick();p.acceptSeek=false;e.receive(frame(20000.0,2));e.tick()
  repeat(100){now+=100;e.tick()};assertEquals(1,p.seeks)
 }

}
