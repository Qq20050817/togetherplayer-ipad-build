package dev.together.poc
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File
@RunWith(AndroidJUnit4::class)
class WatchMemoryPersistenceTest {
 @Test fun deletedSourceDoesNotEraseMemory() {
  val c=InstrumentationRegistry.getInstrumentation().targetContext
  c.getSharedPreferences("watch-memory-v1",0).edit().clear().commit()
  try {
   val m=WatchMemory(c,onlineEnabled=false)
   assertTrue(m.catalog.size>=48)
   val source=File(c.cacheDir,"memory-fixture.mkv");source.writeText("fixture")
   m.record("The.Guilty.2018.DANISH.1080p.mkv")
   m.feedback("guilty2018",5,listOf("悬疑","低血腥"),"喜欢电话推理")
   source.delete()
   val restored=WatchMemory(c,onlineEnabled=false)
   assertEquals(1,restored.records.size);assertEquals(5,restored.records.first().rating);assertEquals("喜欢电话推理",restored.records.first().note)
   restored.record("罪人");assertEquals(1,restored.records.size)
   assertFalse(FilmTaste.suggestions(restored.records,restored.catalog,emptySet()).any{it.film.id=="guilty2018"})
  }finally{c.getSharedPreferences("watch-memory-v1",0).edit().clear().commit()}
 }
}
