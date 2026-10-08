package dev.together.poc

import android.content.ContentValues
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class LocalDocumentPlaybackTest {
 private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
 @Test fun mp4PickedThroughSystemFilesRendersAndSeeks()=pickAndPlay("mp4","video/mp4")
 @Test fun mkvPickedThroughSystemFilesRendersAndSeeks()=pickAndPlay("mkv","video/x-matroska")
 private fun room()=JSONObject().put("roomId","local-document-test").put("hostId","peer").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1).put("mediaUrl","https://example.invalid/fixture.mp4").put("title","Local test")
 private fun welcome(activity:MainActivity) {
  activity.javaClass.getDeclaredMethod("receive",JSONObject::class.java,Double::class.javaPrimitiveType).apply{isAccessible=true}.invoke(activity,JSONObject().put("type","WELCOME").put("room",room()),0.0)
 }
 private fun player(activity:MainActivity)=activity.javaClass.getDeclaredField("player").apply{isAccessible=true}.get(activity) as ExoPlayer
 private fun pickAndPlay(extension:String,mime:String) {
  val context=instrumentation.targetContext;val resolver=context.contentResolver
  val name="TOGETHER-LOCAL-TEST.$extension"
  val values=ContentValues().apply {put(MediaStore.Downloads.DISPLAY_NAME,name);put(MediaStore.Downloads.MIME_TYPE,mime);put(MediaStore.Downloads.RELATIVE_PATH,"Download/");put(MediaStore.Downloads.IS_PENDING,1)}
  val fixture=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values)!!
  try {
   instrumentation.context.assets.open("local-test.$extension").use{source->resolver.openOutputStream(fixture)!!.use{source.copyTo(it)}}
   resolver.update(fixture,ContentValues().apply{put(MediaStore.Downloads.IS_PENDING,0)},null,null)
   ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
    scenario.onActivity {activity->
     welcome(activity)
     activity.javaClass.getDeclaredMethod("importLocalMovie",Boolean::class.javaPrimitiveType).apply{isAccessible=true}.invoke(activity,false)
    }
    val device=UiDevice.getInstance(instrumentation)
    device.wait(Until.hasObject(By.pkg("com.google.android.documentsui")),5000)
    var item=device.wait(Until.findObject(By.text(name)),5000)
    if(item==null){
     clickStable(device,By.desc("Show roots"),3000)
     clickStable(device,By.text("Downloads"),3000)
     item=device.wait(Until.findObject(By.text(name)),5000)
    }
    assertNotNull("System Files did not show the downloaded fixture: "+device.currentPackageName,item)
    assertTrue("Current Files item must remain selectable",clickStable(device,By.text(name),5000))
    assertTrue("Picker must return to app",device.wait(Until.hasObject(By.pkg("dev.together.poc")),5000))
    scenario.onActivity{welcome(it)}
    var selected=""
    for(attempt in 0 until 60){
     scenario.onActivity {activity->selected=activity.javaClass.getDeclaredField("localFileUri").apply{isAccessible=true}.get(activity) as String}
     if(selected.isNotBlank())break;SystemClock.sleep(100)
    }
    assertTrue("The actual picker result must be content://, not a raw computer path",selected.startsWith("content://"))
    val frame=CountDownLatch(1);var failure:String?=null
    scenario.onActivity{activity->player(activity).apply{
     addListener(object:Player.Listener {override fun onRenderedFirstFrame(){frame.countDown()};override fun onPlayerError(error:androidx.media3.common.PlaybackException){failure=error.errorCodeName;frame.countDown()}})
     seekTo(1500);play()
    }}
    assertTrue("No rendered video frame after real Files selection",frame.await(15,TimeUnit.SECONDS));assertNull(failure)
    scenario.onActivity{activity->assertTrue(player(activity).duration>0);assertEquals(160,player(activity).videoFormat!!.width);player(activity).stop()}
   }
  } finally {resolver.delete(fixture,null,null)}
 }
 // DocumentsUI replaces nodes while thumbnails/metadata arrive. Re-query only
 // stale accessibility nodes; still require the actual content URI, decoded frame and seek.
 private fun clickStable(device:UiDevice,selector:BySelector,timeout:Long):Boolean {
  val deadline=SystemClock.elapsedRealtime()+timeout
  while(SystemClock.elapsedRealtime()<deadline) {
   try {val current=device.wait(Until.findObject(selector),500);if(current!=null){current.click();return true}}
   catch(_:StaleObjectException) {SystemClock.sleep(80)}
  }
  return false
 }
 @Test fun missingLocalFileReportsIOFileNotFoundNotDecoderFailure() {
  val failed=CountDownLatch(1);var code=0;var p:ExoPlayer?=null
  instrumentation.runOnMainSync{
   p=ExoPlayer.Builder(instrumentation.targetContext).build()
   p!!.addListener(object:Player.Listener{override fun onPlayerError(error:androidx.media3.common.PlaybackException){code=error.errorCode;failed.countDown()}})
   p!!.setMediaItem(androidx.media3.common.MediaItem.fromUri(Uri.fromFile(java.io.File(instrumentation.targetContext.cacheDir,"fixture-does-not-exist.mp4"))));p!!.prepare()
  }
  try{assertTrue(failed.await(10,TimeUnit.SECONDS));assertEquals(androidx.media3.common.PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,code)}
  finally{instrumentation.runOnMainSync{p?.release()}}
 }
}
