package dev.together.poc

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HdrDiagnosticReportInstrumentedTest {
 @Test fun reportSaveDialogIsAvailableWithoutChangingPlayback(){
  val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
  ActivityScenario.launch(MainActivity::class.java).use {scenario->
   scenario.onActivity {activity->
    val method=activity.javaClass.getDeclaredMethod("showHdrDiagnosticExport")
    method.isAccessible=true
    method.invoke(activity)
   }
   assertNotNull(device.wait(Until.findObject(By.text("导出 HDR 诊断")),5000))
   assertNotNull(device.findObject(By.text("选择保存位置")))
   scenario.onActivity {activity->
    val field=activity.javaClass.getDeclaredField("playback").apply{isAccessible=true}
    val player=field.get(activity) as CompatiblePlayback
    assertFalse("Diagnostics must not activate another decoder",player.compatibleActive)
   }
  }
 }
}
