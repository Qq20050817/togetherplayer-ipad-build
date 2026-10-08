package dev.together.poc
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.scrollTo
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.assertion.ViewAssertions.*
import androidx.test.espresso.matcher.ViewMatchers.*
import androidx.test.espresso.matcher.RootMatchers.isDialog
import org.hamcrest.Matchers.not
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
import android.content.pm.ActivityInfo
import android.os.SystemClock

@RunWith(AndroidJUnit4::class)
class WatchInterfaceTest {
 private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
 @Before fun prepareDevice() {
  // Dismiss only the emulator launcher; never suppress errors from our app.
  for(command in listOf("am force-stop com.android.launcher3","input keyevent KEYCODE_WAKEUP","wm dismiss-keyguard")) {
   android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).use {it.readBytes()}
  }
 }
 @Test fun testPortraitLandscapeAndFullscreen() {
  val launch=android.content.Intent(instrumentation.targetContext,MainActivity::class.java).putExtra("uiTestSlow",true)
  ActivityScenario.launch<MainActivity>(launch).use {scenario->
   scenario.onActivity {it.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_PORTRAIT};SystemClock.sleep(1000)
   onView(withContentDescription("房间 / 设置")).check(matches(isDisplayed()))
   scenario.onActivity {activity->
    activity.javaClass.getDeclaredField("credentials").apply {isAccessible=true}.set(activity,org.json.JSONObject().put("userId","ui-me"))
    val c=activity.javaClass.getDeclaredField("chat").apply {isAccessible=true}.get(activity) as ChatEngine
    c.accept(ChatMessage(1,"ui-peer","好友","这个画面真好看","fixture-peer",System.currentTimeMillis().toDouble()),false)
    c.accept(ChatMessage(2,"ui-me","我","一起看下一部！","fixture-me",System.currentTimeMillis().toDouble()),true)
    activity.javaClass.getDeclaredMethod("renderChat").apply {isAccessible=true}.invoke(activity)
   };SystemClock.sleep(500);capture("01-portrait")
   onView(withContentDescription("静音 / 恢复音量")).perform(click())
   scenario.onActivity {activity->val p=activity.javaClass.getDeclaredField("player").apply {isAccessible=true}.get(activity) as androidx.media3.exoplayer.ExoPlayer;assertEquals(0f,p.volume,0.001f)}
   onView(withContentDescription("静音 / 恢复音量")).perform(click())
   onView(withContentDescription("房间 / 设置")).perform(click());onView(withText("创建")).check(matches(isDisplayed()));onView(withText("选择本地影片")).perform(scrollTo()).check(matches(isDisplayed()));capture("02-room-settings")
   onView(withText("一起看")).perform(click())
   scenario.onActivity {it.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE};SystemClock.sleep(1000);capture("03-landscape")
   // Espresso waits for delayed main-loop messages; inspect the timed overlay
   // synchronously so a successful hide cannot invalidate the initial assertion.
   scenario.onActivity {activity->
    described(activity.window.decorView,"全屏")!!.performClick()
    val decor=fullscreen(activity).window!!.decorView
    assertTrue(described(decor,"退出全屏")!!.isShown)
    assertTrue(described(decor,"发弹幕")!!.isShown)
    assertNull(textView(decor,"房间 / 设置"))
   };SystemClock.sleep(400)
   scenario.onActivity {activity->
    val box=activity.javaClass.getDeclaredField("videoBox").apply {isAccessible=true}.get(activity) as android.view.View
    val bar=activity.javaClass.getDeclaredField("fullscreenControls").apply {isAccessible=true}.get(activity) as android.view.View
    val videoPosition=IntArray(2);val barPosition=IntArray(2);box.getLocationOnScreen(videoPosition);bar.getLocationOnScreen(barPosition)
    assertTrue(videoPosition[1]+box.height<=barPosition[1]+1)
    val mic=described(fullscreen(activity).window!!.decorView,"启用语音弹幕")!!;val micPosition=IntArray(2);mic.getLocationOnScreen(micPosition)
    assertTrue(micPosition[0]+mic.width/2>fullscreen(activity).window!!.decorView.width*0.7)
    for(control in listOf(mic,textView(fullscreen(activity).window!!.decorView,"10↪")!!,described(fullscreen(activity).window!!.decorView,"退出全屏")!!)){val where=IntArray(2);control.getLocationOnScreen(where);assertTrue(where[0]>=videoPosition[0]);assertTrue(where[0]+control.width<=videoPosition[0]+box.width)}
   };capture("04-fullscreen-controls")
   // Wait for the idle deadline after any platform focus transition; dialog
   // focus changes pause the timer, so a fixed 13-second sleep is flaky.
   var hidden=false
   for(attempt in 0 until 200){
    scenario.onActivity {activity->hidden=!described(fullscreen(activity).window!!.decorView,"退出全屏")!!.isShown}
    if(hidden)break
    SystemClock.sleep(100)
   }
   assertTrue("Idle controls must eventually hide without interaction",hidden);capture("05-fullscreen-hidden")
   scenario.onActivity {activity->
    val box=activity.javaClass.getDeclaredField("videoBox").apply {isAccessible=true}.get(activity) as android.view.View
    assertTrue(box.performClick())
    val decor=fullscreen(activity).window!!.decorView
    assertTrue(described(decor,"退出全屏")!!.isShown)
    assertTrue(described(decor,"发弹幕")!!.isShown)
    described(decor,"退出全屏")!!.performClick()
   }
   onView(withContentDescription("房间 / 设置")).check(matches(isDisplayed()))
   scenario.onActivity {activity->activity.javaClass.getDeclaredField("credentials").apply {isAccessible=true}.set(activity,null)}
  }
 }
 @Test fun testPrivateRoomStopsOldMovieAndBaiduAuthorizationControlsWork() {
  ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
   var adapter:BaiduSourceAdapter?=null
   scenario.onActivity {activity->
    val p=activity.javaClass.getDeclaredField("player").apply {isAccessible=true}.get(activity) as androidx.media3.exoplayer.ExoPlayer
    p.setMediaItem(androidx.media3.common.MediaItem.fromUri("file:///old-test.mp4"))
    val ref=BaiduMediaReference.create("a".repeat(32),5L)!!
    val room=org.json.JSONObject().put("roomId","fixture-room").put("hostId","peer").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1).put("mediaUrl",ref.value).put("title","转存影片")
    val event=org.json.JSONObject().put("type","STATE").put("room",room)
    activity.javaClass.getDeclaredMethod("receive",org.json.JSONObject::class.java,Double::class.javaPrimitiveType).apply {isAccessible=true}.invoke(activity,event,0.0)
    assertEquals(0,p.mediaItemCount)
    val notice=activity.javaClass.getDeclaredField("notice").apply {isAccessible=true}.get(activity) as android.widget.TextView
    assertTrue(notice.text.contains("等待百度选片"))
    adapter=BaiduSourceAdapter()
    BaiduBrowserDialog(activity,adapter!!,"转存影片",{_,_->false},{}).show()
   }
   onView(withText("打开官方体验授权页")).check(matches(isDisplayed()))
   onView(withText("应用授权并读取文件")).perform(scrollTo(),click())
   onView(withText("授权格式无效；不要输入密码或 Cookie。")).perform(scrollTo()).check(matches(isDisplayed()))
   onView(withText("返回")).perform(click())
   adapter?.close()
  }
 }
 @Test fun testBaiduEntryOpensWithoutRoomAndDuringReconnect() {
  ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
   onView(withContentDescription("房间 / 设置")).perform(click())
   onView(withText("百度网盘 · 授权并选择房间影片")).perform(scrollTo(),click())
   onView(withText("百度网盘 · 房间选片")).check(matches(isDisplayed()))
   onView(withText("打开官方体验授权页")).check(matches(isDisplayed()))
   onView(withText("返回")).perform(click())
   scenario.onActivity {activity->
    val room=org.json.JSONObject().put("roomId","reconnecting-room").put("hostId","peer").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1).put("mediaUrl",BaiduMediaReference.create("a".repeat(32),5L)!!.value).put("title","转存影片")
    activity.javaClass.getDeclaredMethod("receive",org.json.JSONObject::class.java,Double::class.javaPrimitiveType).apply {isAccessible=true}.invoke(activity,org.json.JSONObject().put("type","STATE").put("room",room),0.0)
    activity.javaClass.getDeclaredField("connected").apply {isAccessible=true}.setBoolean(activity,false)
   }
   onView(withText("百度网盘 · 授权并选择房间影片")).perform(scrollTo(),click())
   onView(withText("百度网盘 · 房间选片")).check(matches(isDisplayed()))
   onView(withText("返回")).perform(click())
  }
 }
 @Test fun testMissingBrowserShowsMessageAndAllowsCopyingAuthorizationPage() {
  ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
   val adapter=BaiduSourceAdapter()
   scenario.onActivity {activity->BaiduBrowserDialog(activity,adapter,"",{_,_->false},{},{throw android.content.ActivityNotFoundException()}).show()}
   onView(withText("打开官方体验授权页")).perform(click())
   onView(withText("没有可用浏览器。请复制授权页链接，在浏览器中打开。")).perform(scrollTo()).check(matches(isDisplayed()))
   onView(withText("复制授权页链接")).perform(scrollTo(),click())
   scenario.onActivity {activity->
    val clipboard=activity.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
    assertEquals(BaiduSourceAdapter.AUTHORIZE,clipboard.primaryClip!!.getItemAt(0).text.toString())
   }
   onView(withText("返回")).perform(click());adapter.close()
  }
 }
 @Test fun testFullscreenSettingsRemainVisiblePastIdleDeadline() {
  ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
   scenario.onActivity {it.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE};SystemClock.sleep(1000)
   scenario.onActivity {activity->
    described(activity.window.decorView,"全屏")!!.performClick()
   };SystemClock.sleep(400)
   scenario.onActivity {activity->
    val decor=fullscreen(activity).window!!.decorView
    for(label in listOf("音轨","字幕","导入字幕","字幕调整","弹幕字号","弹幕速度"))assertTrue("Fullscreen tool must be shown: $label",describedShown(decor,label)!=null)
    described(decor,"弹幕速度")!!.performClick()
   }
   SystemClock.sleep(11000)
   scenario.onActivity {activity->assertTrue("Settings must block auto-hide",described(fullscreen(activity).window!!.decorView,"退出全屏")!!.isShown)}
   onView(withText("完成")).inRoot(isDialog()).check(matches(isDisplayed())).perform(click())
   scenario.onActivity {activity->assertTrue(described(fullscreen(activity).window!!.decorView,"退出全屏")!!.isShown)}
   var downTime=0L;var touchX=0f;var touchY=0f
   scenario.onActivity {activity->
    val dialog=fullscreen(activity);val tool=describedShown(dialog.window!!.decorView,"弹幕速度")!!
    val point=IntArray(2);tool.getLocationInWindow(point);touchX=point[0]+tool.width/2f;touchY=point[1]+tool.height/2f;downTime=SystemClock.uptimeMillis()
    val event=android.view.MotionEvent.obtain(downTime,downTime,android.view.MotionEvent.ACTION_DOWN,touchX,touchY,0)
    dialog.window!!.callback.dispatchTouchEvent(event);event.recycle()
   }
   SystemClock.sleep(11000)
   scenario.onActivity {activity->
    val dialog=fullscreen(activity);assertTrue("Holding a control must block hiding",describedShown(dialog.window!!.decorView,"退出全屏")!=null)
    val event=android.view.MotionEvent.obtain(downTime,SystemClock.uptimeMillis(),android.view.MotionEvent.ACTION_CANCEL,touchX,touchY,0);dialog.window!!.callback.dispatchTouchEvent(event);event.recycle()
   }
   capture("06-fullscreen-speed-controls")
  }
 }
 private fun fullscreen(activity: MainActivity)=activity.javaClass.getDeclaredField("fullscreenDialog").apply {isAccessible=true}.get(activity) as android.app.Dialog
 @Test fun testIdlePlayerIsNotReloadedByPeriodicSnapshotsAndManualRetryWorks() {
  ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
   scenario.onActivity {activity->
    val p=activity.javaClass.getDeclaredField("player").apply {isAccessible=true}.get(activity) as androidx.media3.exoplayer.ExoPlayer
    val url="https://example.org/failed.mkv"
    activity.javaClass.getDeclaredField("loadedURL").apply {isAccessible=true}.set(activity,url)
    val room=org.json.JSONObject().put("roomId","failed-room").put("hostId","peer").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1).put("mediaUrl",url).put("title","失败影片")
    val receive=activity.javaClass.getDeclaredMethod("receive",org.json.JSONObject::class.java,Double::class.javaPrimitiveType).apply {isAccessible=true}
    repeat(50){receive.invoke(activity,org.json.JSONObject().put("type","STATE").put("room",room),0.0)}
    assertEquals("Idle/error must not restart on SYNC",0,p.mediaItemCount)
    activity.javaClass.getDeclaredMethod("retryPlayback").apply {isAccessible=true}.invoke(activity)
    assertEquals(1,p.mediaItemCount)
    p.stop()
   }
  }
 }
 @Test fun testLocalFileFingerprintAndPickerReturnApplyAfterReconnect() {
  val fixture=java.io.File(instrumentation.targetContext.cacheDir,"picked-local-movie.mka")
  instrumentation.context.assets.open("dts-test.mka").use {source->fixture.outputStream().use {source.copyTo(it)}}
  val uri=android.net.Uri.fromFile(fixture)
  try {ActivityScenario.launch<MainActivity>(MainActivity::class.java).use {scenario->
   scenario.onActivity {activity->
    activity.javaClass.getDeclaredField("pendingLocalRoom").apply {isAccessible=true}.set(activity,"local-room")
    activity.javaClass.getDeclaredField("pendingLocalMedia").apply {isAccessible=true}.set(activity,"https://example.org/movie.mp4")
   }
   scenario.recreate()
   scenario.onActivity {activity->
    assertEquals("local-room",activity.javaClass.getDeclaredField("pendingLocalRoom").apply {isAccessible=true}.get(activity))
    assertEquals("https://example.org/movie.mp4",activity.javaClass.getDeclaredField("pendingLocalMedia").apply {isAccessible=true}.get(activity))
    val identity=activity.javaClass.getDeclaredMethod("localFileIdentity",android.net.Uri::class.java).apply {isAccessible=true}.invoke(activity,uri) as Pair<*,*>
    assertEquals(fixture.length(),identity.first);assertEquals(32,(identity.second as String).length)
    fun field(name:String,value:Any){activity.javaClass.getDeclaredField(name).apply {isAccessible=true}.set(activity,value)}
    field("pendingLocalRoom","local-room");field("pendingLocalMedia","https://example.org/movie.mp4");field("connected",false)
    val returned=activity.javaClass.getDeclaredMethod("onActivityResult",Int::class.javaPrimitiveType,Int::class.javaPrimitiveType,android.content.Intent::class.java).apply {isAccessible=true}
    returned.invoke(activity,702,android.app.Activity.RESULT_OK,android.content.Intent().setData(uri).addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION))
    assertNotNull(activity.javaClass.getDeclaredField("pendingLocalMovie").apply {isAccessible=true}.get(activity))
    val room=org.json.JSONObject().put("roomId","local-room").put("hostId","peer").put("version",1).put("executeAt",0).put("updatedAt",0).put("state","paused").put("position",0).put("playbackRate",1).put("mediaUrl","https://example.org/movie.mp4").put("title","本地影片")
    activity.javaClass.getDeclaredMethod("receive",org.json.JSONObject::class.java,Double::class.javaPrimitiveType).apply {isAccessible=true}.invoke(activity,org.json.JSONObject().put("type","WELCOME").put("room",room),0.0)
   }
   var selected=false
   for(attempt in 0 until 50){
    scenario.onActivity {activity->selected=activity.javaClass.getDeclaredField("localFileUri").apply {isAccessible=true}.get(activity)==uri.toString()}
    if(selected)break
    Thread.sleep(100)
   }
   assertTrue("File-picker result must be applied after WELCOME",selected)
  }} finally {fixture.delete()}
 }
 @Test fun testBundledFfmpegDecodesDtsAudio() {
  val fixture=java.io.File(instrumentation.targetContext.cacheDir,"dts-test.mka")
  instrumentation.context.assets.open("dts-test.mka").use {source->fixture.outputStream().use {source.copyTo(it)}}
  val decoded=java.util.concurrent.CountDownLatch(1)
  var p:androidx.media3.exoplayer.ExoPlayer?=null;var failure:String?=null
  instrumentation.runOnMainSync {
   assertTrue(androidx.media3.decoder.ffmpeg.FfmpegLibrary.isAvailable())
   assertTrue(androidx.media3.decoder.ffmpeg.FfmpegLibrary.supportsFormat("audio/vnd.dts"))
   val renderers=PlaybackRenderers.create(instrumentation.targetContext)
   p=androidx.media3.exoplayer.ExoPlayer.Builder(instrumentation.targetContext,renderers).build()
   p!!.addListener(object:androidx.media3.common.Player.Listener {
    override fun onIsPlayingChanged(playing:Boolean){if(playing)decoded.countDown()}
    override fun onPlayerError(error:androidx.media3.common.PlaybackException){failure=error.errorCodeName;decoded.countDown()}
   })
   p!!.setMediaItem(androidx.media3.common.MediaItem.fromUri(android.net.Uri.fromFile(fixture)));p!!.prepare();p!!.play()
  }
  try {assertTrue("DTS playback timed out",decoded.await(15,java.util.concurrent.TimeUnit.SECONDS));assertNull(failure)}
  finally {instrumentation.runOnMainSync {p?.release()};fixture.delete()}
 }
 private fun describedShown(view:android.view.View,description:String):android.view.View? {
  if(view.contentDescription?.toString()==description && view.isShown)return view
  if(view is android.view.ViewGroup)for(index in 0 until view.childCount){describedShown(view.getChildAt(index),description)?.let {return it}}
  return null
 }
 private fun described(view: android.view.View,description: String): android.view.View? {
  if(view.contentDescription?.toString()==description)return view
  if(view is android.view.ViewGroup)for(index in 0 until view.childCount){described(view.getChildAt(index),description)?.let {return it}}
  return null
 }
 private fun textView(view: android.view.View,text: String): android.widget.TextView? {
  if(view is android.widget.TextView && view.text.toString()==text)return view
  if(view is android.view.ViewGroup)for(index in 0 until view.childCount){textView(view.getChildAt(index),text)?.let {return it}}
  return null
 }
 private fun capture(name: String){
  val bitmap=instrumentation.uiAutomation.takeScreenshot();assertNotNull(bitmap)
  val resolver=instrumentation.targetContext.contentResolver
  val values=android.content.ContentValues().apply {put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,"$name.png");put(android.provider.MediaStore.Images.Media.MIME_TYPE,"image/png");put(android.provider.MediaStore.Images.Media.RELATIVE_PATH,"Pictures/TogetherUITests")}
  val uri=resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values)!!
  resolver.openOutputStream(uri)!!.use {bitmap!!.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap?.recycle()
 }
}
