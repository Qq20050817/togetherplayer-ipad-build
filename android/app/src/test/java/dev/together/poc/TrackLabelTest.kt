package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
class TrackLabelTest {
 @Test fun chineseScriptRequiresTagsOrTitles() {
  assertTrue(TrackLabel.label("CHS","zh","text/vtt",ordinal=1,subtitle=true).contains("简体中文"))
  assertTrue(TrackLabel.label(null,"zh-Hant","text/vtt",ordinal=2,subtitle=true).contains("繁体中文"))
  assertTrue(TrackLabel.label(null,"chi","text/vtt",ordinal=1,subtitle=true).contains("简繁未标明"))
 }
 @Test fun sourceCodecAndChannelsRemainVisible() {
  val label=TrackLabel.label("English","eng","audio/vnd.dts.hd",8,2,false)
  assertTrue(label.contains("英语"));assertTrue(label.contains("DTS-HD"));assertTrue(label.contains("7.1"));assertFalse(label.contains("Atmos"))
 }
}
