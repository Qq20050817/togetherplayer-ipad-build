package dev.together.poc
import android.widget.LinearLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ChatPresentationTest {
 @Test fun incomingChatReusesNinetyNineExistingNativeRows() {
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   scenario.onActivity {activity->
    val chat=activity.javaClass.getDeclaredField("chat").apply{isAccessible=true}.get(activity) as ChatEngine
    val bubbles=activity.javaClass.getDeclaredField("chatBubbles").apply{isAccessible=true}.get(activity) as LinearLayout
    val render=activity.javaClass.getDeclaredMethod("renderChat").apply{isAccessible=true}
    chat.reset("performance-fixture")
    for(i in 1L..100L)chat.accept(ChatMessage(i,"peer","好友","聊天 $i","perf-$i",0.0),false)
    render.invoke(activity);assertEquals(100,bubbles.childCount)
    val previous=List(100){bubbles.getChildAt(it)}
    chat.accept(ChatMessage(101,"peer","好友","新消息","perf-101",0.0),false);render.invoke(activity)
    assertEquals(100,bubbles.childCount)
    for(i in 0 until 99)assertSame(previous[i+1],bubbles.getChildAt(i))
    val current=List(100){bubbles.getChildAt(it)}
    repeat(10){render.invoke(activity)}
    for(i in 0 until 100)assertSame(current[i],bubbles.getChildAt(i))
    chat.reset("another-room");render.invoke(activity);assertEquals(1,bubbles.childCount)
   }
  }
 }
}
