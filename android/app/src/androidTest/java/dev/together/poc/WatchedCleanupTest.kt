package dev.together.poc

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WatchedCleanupTest {
 @Test fun realFolderGrantDeletesOnlyConfirmedMovieAndSubtitles() {
  val i=InstrumentationRegistry.getInstrumentation();val resolver=i.targetContext.contentResolver
  val folder="TogetherCleanup-"+System.currentTimeMillis()
  val created=mutableListOf<Uri>()
  fun write(name:String,contents:ByteArray):Uri {
   val values=ContentValues().apply{put(MediaStore.Downloads.DISPLAY_NAME,name);put(MediaStore.Downloads.MIME_TYPE,"application/octet-stream");put(MediaStore.Downloads.RELATIVE_PATH,"Download/$folder/");put(MediaStore.Downloads.IS_PENDING,1)}
   val uri=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values)!!;created.add(uri)
   resolver.openOutputStream(uri)!!.use{it.write(contents)}
   resolver.update(uri,ContentValues().apply{put(MediaStore.Downloads.IS_PENDING,0)},null,null)
   return uri
  }
  try {
   write("Film.mp4",i.context.assets.open("local-test.mp4").use{it.readBytes()})
   write("Film.zh-Hans.srt","1\n00:00:00,000 --> 00:00:03,000\n你好\n".toByteArray())
   val keep=write("Other.srt","keep".toByteArray())
   val source=DocumentsContract.buildDocumentUri("com.android.externalstorage.documents","primary:Download/$folder/Film.mp4")
   ActivityScenario.launch(MainActivity::class.java).use {scenario->
    scenario.onActivity{a->
     a.javaClass.getDeclaredField("localFileUri").apply{isAccessible=true}.set(a,source.toString())
     a.javaClass.getDeclaredMethod("beginWatchedCleanup").apply{isAccessible=true}.invoke(a)
    }
    val device=UiDevice.getInstance(i)
    assertNotNull(device.wait(Until.findObject(By.text("选择影片所在文件夹")),5000))
    device.findObject(By.text("选择影片所在文件夹")).click()
    assertTrue(device.wait(Until.hasObject(By.pkg("com.google.android.documentsui")),5000))
    // Navigate through real system folder authorization, never grant broad storage access.
    device.wait(Until.findObject(By.desc("Show roots")),4000)?.click()
    device.wait(Until.findObject(By.text("Downloads")),4000)?.click()
    val target=device.wait(Until.findObject(By.text(folder)),5000)
    assertNotNull("Fixture directory must be selectable",target);target!!.click()
    val use=device.wait(Until.findObject(By.text(java.util.regex.Pattern.compile("use this folder",java.util.regex.Pattern.CASE_INSENSITIVE))),5000)
    assertNotNull("System must offer folder grant",use);use!!.click()
    device.wait(Until.findObject(By.text(java.util.regex.Pattern.compile("allow",java.util.regex.Pattern.CASE_INSENSITIVE))),3000)?.click()
    assertNotNull("Review must include movie",device.wait(Until.findObject(By.textContains("Film.mp4")),8000))
    assertNotNull(device.findObject(By.textContains("Film.zh-Hans.srt")))
    assertNull("Unrelated subtitle must not be offered",device.findObject(By.textContains("Other.srt")))
    device.findObject(By.text("清理所选")).click()
    assertNotNull(device.wait(Until.findObject(By.text("确认删除 2 个本地文件？")),4000))
    device.findObject(By.text("删除")).click()
    assertNotNull("Actual provider deletions must finish",device.wait(Until.findObject(By.textContains("已删除 2 个文件")),8000))
    assertEquals("keep",resolver.openInputStream(keep)!!.bufferedReader().use{it.readText()})
    scenario.onActivity{a->assertEquals("",a.javaClass.getDeclaredField("localFileUri").apply{isAccessible=true}.get(a))}
   }
  } finally {created.forEach{runCatching{resolver.delete(it,null,null)}}}
 }
}
