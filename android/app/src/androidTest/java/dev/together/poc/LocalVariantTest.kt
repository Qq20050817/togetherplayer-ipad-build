package dev.together.poc
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.*
import androidx.media3.common.Player
import android.os.SystemClock
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
@RunWith(AndroidJUnit4::class)
class LocalVariantTest {
 @Test fun mismatchedBytesRequireConfirmationThenRealDurationMustMatch() {
  val i=InstrumentationRegistry.getInstrumentation();val file=java.io.File(i.targetContext.cacheDir,"same-edit-transcode.mp4")
  i.context.assets.open("local-test.mp4").use {s->file.outputStream().use {s.copyTo(it)}}
  try {ActivityScenario.launch(MainActivity::class.java).use {scenario->
   val ref=BaiduMediaReference.create("a".repeat(32),12345678)!!.value
   val room=JSONObject().put("roomId","variant-test").put("hostId","peer").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1).put("duration",8000).put("mediaUrl",ref).put("title","同一剪辑原版")
   fun field(a:MainActivity,name:String)=a.javaClass.getDeclaredField(name).apply{isAccessible=true}.get(a)
   scenario.onActivity {a->a.javaClass.getDeclaredMethod("receive",JSONObject::class.java,Double::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,JSONObject().put("type","WELCOME").put("room",room),0.0);a.javaClass.getDeclaredMethod("useLocalMovie",android.net.Uri::class.java,Int::class.javaPrimitiveType,Boolean::class.javaPrimitiveType).apply{isAccessible=true}.invoke(a,android.net.Uri.fromFile(file),0,false)}
   val device=UiDevice.getInstance(i)
   assertNotNull("Different fingerprint must show review",device.wait(Until.findObject(By.text("使用同一影片的转码版？")),5000))
   scenario.onActivity {a->assertEquals("",field(a,"localFileUri"))}
   device.findObject(By.text("确认同一剪辑")).click()
   var selected=false;var ready=false;val deadline=SystemClock.elapsedRealtime()+15000
   while(!ready && SystemClock.elapsedRealtime()<deadline){scenario.onActivity {a->selected=(field(a,"localFileUri") as String).isNotBlank();val p=field(a,"playback") as CompatiblePlayback;ready=selected && p.playbackState==Player.STATE_READY};SystemClock.sleep(100)}
   assertTrue("Confirmed transcode never loaded",selected);assertTrue(ready)
   scenario.onActivity {a->assertEquals(ref,field(a,"baiduSourceID"));val check=a.javaClass.getDeclaredMethod("variantCheck").apply{isAccessible=true};assertEquals(MovieVariantPolicy.DurationCheck.COMPATIBLE,check.invoke(a));a.javaClass.getDeclaredField("variantDuration").apply{isAccessible=true}.set(a,30000.0);assertEquals(MovieVariantPolicy.DurationCheck.DIFFERENT,check.invoke(a));(field(a,"playback") as CompatiblePlayback).stop()}
  }} finally {file.delete()}
 }
}
