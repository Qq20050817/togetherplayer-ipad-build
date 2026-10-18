package dev.together.poc

import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.Request
import okhttp3.WebSocket
import okio.ByteString
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomSessionStabilityTest {
 private class Socket(private val acceptsSend:Boolean=true):WebSocket {
  var cancelled=0
  override fun request()=Request.Builder().url("https://example.invalid/ws").build()
  override fun queueSize()=0L
  override fun send(text:String)=acceptsSend
  override fun send(bytes:ByteString)=acceptsSend
  override fun close(code:Int,reason:String?)=true
  override fun cancel(){cancelled++}
 }
 private fun get(a:MainActivity,name:String):Any?=a.javaClass.getDeclaredField(name).apply{isAccessible=true}.get(a)
 private fun set(a:MainActivity,name:String,value:Any?){a.javaClass.getDeclaredField(name).apply{isAccessible=true}.set(a,value)}
 private fun receive(a:MainActivity,obj:JSONObject){
  a.javaClass.getDeclaredMethod("receive",JSONObject::class.java,Double::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,obj,0.0)
 }
 private fun reconnect(a:MainActivity,g:Int){
  a.javaClass.getDeclaredMethod("reconnect",Int::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,g)
 }
 private fun scenario(body:(MainActivity)->Unit){
  val context=InstrumentationRegistry.getInstrumentation().targetContext
  context.getSharedPreferences("MainActivity",0).edit().clear().commit()
  ActivityScenario.launch(MainActivity::class.java).use { scenario->scenario.onActivity { a->
   set(a,"credentials",JSONObject().put("roomId","stability-room").put("userId","host").put("token","test-only"))
   set(a,"ws",Socket())
   body(a)
  }}
 }
 private fun room(version:Int,title:String="当前影片",media:String="a"):JSONObject {
  val timeline=JSONObject().put("state","paused").put("position",0).put("updatedAt",0).put("playbackRate",1)
  return JSONObject(timeline.toString()).put("roomId","stability-room").put("hostId","host")
   .put("version",version).put("executeAt",0).put("before",timeline).put("title",title)
   .put("mediaUrl","baidu://"+media.repeat(32)+"/"+"b".repeat(32)+"/5")
 }
 @Test fun staleSnapshotDoesNotChangeFilmTitleOrQuestionAndStillClearsAck(){scenario {a->
  receive(a,JSONObject().put("type","WELCOME").put("room",room(3)))
  set(a,"plotPoll",JSONObject().put("id","current-poll"))
  set(a,"inFlight",JSONObject().put("type","PAUSE"));set(a,"flightSequence",7L)
  val source=get(a,"loadedURL")
  receive(a,JSONObject().put("type","STATE").put("room",room(2,"旧影片","c"))
   .put("poll",JSONObject.NULL).put("ackUserId","host").put("ackSequence",7))
  assertEquals(source,get(a,"loadedURL"))
  assertEquals("当前影片",(get(a,"roomTitle") as TextView).text.toString())
  assertEquals("current-poll",(get(a,"plotPoll") as JSONObject).getString("id"))
  assertEquals(3L,(get(a,"engine") as SyncEngine).version)
  assertNull(get(a,"inFlight"))
 }}
 @Test fun staleDisconnectCallbackCannotResetSessionTwice(){scenario {a->
  val socket=Socket();set(a,"ws",socket);set(a,"connected",true)
  val generation=get(a,"generation") as Int
  reconnect(a,generation)
  assertEquals(generation+1,get(a,"generation"))
  assertFalse(get(a,"connected") as Boolean);assertNull(get(a,"ws"))
  assertEquals(1,socket.cancelled)
  reconnect(a,generation)
  assertEquals(generation+1,get(a,"generation"));assertEquals(1,get(a,"attempt"))
 }}
 @Test fun rejectedSocketSendEntersRecoveryInsteadOfLeavingCommandInFlight(){scenario {a->
  val socket=Socket(false);set(a,"ws",socket);set(a,"connected",true)
  set(a,"inFlight",JSONObject().put("type","PLAY"))
  val generation=get(a,"generation") as Int
  a.javaClass.getDeclaredMethod("send",JSONObject::class.java).apply{isAccessible=true}
   .invoke(a,JSONObject().put("type","PLAY"))
  assertEquals(generation+1,get(a,"generation"));assertFalse(get(a,"connected") as Boolean)
  assertNull(get(a,"inFlight"));assertEquals(1,socket.cancelled)
 }}
}
