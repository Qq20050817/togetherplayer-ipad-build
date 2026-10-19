package dev.together.poc

import android.app.Dialog
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import okhttp3.Request
import okhttp3.WebSocket
import okio.ByteString
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InstantControlAndQuestionRailTest {
 // Keep the transport connected but deliberately never deliver an ACK.
 private class UnacknowledgedSocket:WebSocket {
  val sent=mutableListOf<JSONObject>()
  override fun request()=Request.Builder().url("https://example.invalid/ws").build()
  override fun queueSize()=0L
  override fun send(text:String):Boolean {sent.add(JSONObject(text));return true}
  override fun send(bytes:ByteString)=true
  override fun close(code:Int,reason:String?)=true
  override fun cancel(){}
 }
 private fun field(a:MainActivity,name:String)=a.javaClass.getDeclaredField(name).apply{isAccessible=true}
 @Test fun guestControlsApplyBeforeRoomAcknowledgement() {
  val i=InstrumentationRegistry.getInstrumentation()
  val movie=java.io.File(i.targetContext.cacheDir,"instant-control.mp4")
  i.context.assets.open("local-test.mp4").use{input->movie.outputStream().use{input.copyTo(it)}}
  val socket=UnacknowledgedSocket()
  try {ActivityScenario.launch(MainActivity::class.java).use{scenario->
   scenario.onActivity{a->
    field(a,"credentials").set(a,JSONObject().put("roomId","instant-test").put("userId","guest").put("token","a".repeat(64)))
    field(a,"ws").set(a,socket)
    val clock=field(a,"clock").get(a) as ClockSync;val now=clock.localNow()
    val room=JSONObject().put("roomId","instant-test").put("hostId","host").put("version",1).put("executeAt",now).put("updatedAt",now).put("state","paused").put("position",0).put("playbackRate",1).put("mediaUrl","https://example.invalid/movie.mp4")
    a.javaClass.getDeclaredMethod("receive",JSONObject::class.java,Double::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,JSONObject().put("type","WELCOME").put("instantControlVersion",1).put("room",room),now)
    clock.add(now,now,now,now)
    val playback=field(a,"playback").get(a) as CompatiblePlayback
    playback.setMediaItem(androidx.media3.common.MediaItem.fromUri(movie.toURI().toString()));playback.prepare()
   }
   var ready=false
   for(n in 0..<60){scenario.onActivity{a->ready=(field(a,"playback").get(a) as CompatiblePlayback).playbackState==androidx.media3.common.Player.STATE_READY};if(ready)break;Thread.sleep(100)}
   assertTrue("real local fixture must become ready",ready)
   scenario.onActivity{a->
    val control=a.javaClass.getDeclaredMethod("control",String::class.java,Double::class.javaPrimitiveType).apply{isAccessible=true}
    val playback=field(a,"playback").get(a) as CompatiblePlayback
    assertEquals(true,field(a,"connected").get(a))
    control.invoke(a,"PLAY",0.0)
    assertTrue("local playback must start without an ACK",playback.playWhenReady)
    assertTrue("PLAY must be sent while its acknowledgement is still absent",socket.sent.any{it.optString("type")=="INSTANT_CONTROL" && it.getJSONObject("data").getString("type")=="PLAY"})
    val flight=field(a,"inFlight").get(a) as JSONObject
    assertEquals("INSTANT_CONTROL",flight.optString("type"));assertEquals("PLAY",flight.getJSONObject("data").getString("type"))
    control.invoke(a,"PAUSE",0.0);assertFalse(playback.playWhenReady)
    assertEquals(false,field(a,"optimisticPlaying").get(a))
   }
  }}finally{movie.delete()}
 }
 @Test fun questionRailReservesVideoSpaceAndRestoresItOnClose() {
  ActivityScenario.launch(MainActivity::class.java).use{scenario->
   scenario.onActivity{a->
    val poll=JSONObject().put("id","rail-test").put("question","刚才的两种解释为什么矛盾？").put("options",org.json.JSONArray(listOf("动机","身份"))).put("waitingForAnswers",true)
    field(a,"plotPoll").set(a,poll)
    a.javaClass.getDeclaredMethod("showFullscreen").apply{isAccessible=true}.invoke(a)
    a.javaClass.getDeclaredMethod("showPlotPoll").apply{isAccessible=true}.invoke(a)
   }
   Thread.sleep(600)
   scenario.onActivity{a->
    val drawer=field(a,"plotDrawer").get(a) as Dialog
    val movie=field(a,"videoBox").get(a) as View
    val movieAt=IntArray(2);val drawerAt=IntArray(2)
    movie.getLocationOnScreen(movieAt);drawer.window!!.decorView.getLocationOnScreen(drawerAt)
    assertTrue("question must sit beside the video, not cover it",movieAt[0]+movie.width<=drawerAt[0]+2)
    assertNotEquals(0,a.applicationInfo.icon)
    drawer.dismiss()
   }
   InstrumentationRegistry.getInstrumentation().waitForIdleSync();Thread.sleep(350)
   scenario.onActivity{a->
    assertEquals(0,field(a,"plotReservedWidth").getInt(a))
    (field(a,"fullscreenDialog").get(a) as Dialog).dismiss()
   }
  }
 }
}
