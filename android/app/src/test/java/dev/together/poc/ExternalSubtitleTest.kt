package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
class ExternalSubtitleTest {
 @Test fun overlappingCuesAndBackwardSeek(){val s=ExternalSubtitle.parse("1\n00:00:01,000 --> 00:00:03,000\n你好\n\n2\n00:00:02,000 --> 00:00:04,000\nWorld".toByteArray());assertEquals("你好\nWorld",s.textAt(2500));assertEquals("World",s.textAt(3000));assertEquals("你好",s.textAt(1500));assertEquals("",s.textAt(1500,1000))}
 @Test fun assTextAndDrawing(){val s=ExternalSubtitle.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:03.00,{\\i1}a,b\\N你好\nDialogue: 0,0:00:01.00,0:00:03.00,{\\p1}m 0 0".toByteArray());assertEquals("a,b\n你好",s.textAt(2000))}
 @Test fun vttAndEncoding(){val input="WEBVTT\n\nNOTE ignore\n\n1\n00:01.000 --> 00:02.000 align:start\n中文";assertEquals("中文",ExternalSubtitle.parse(input.toByteArray(charset("GB18030"))).textAt(1500));val bytes=byteArrayOf(-1,-2)+input.toByteArray(Charsets.UTF_16LE);assertEquals("中文",ExternalSubtitle.parse(bytes).textAt(1500))}
 @Test(expected=IllegalArgumentException::class) fun invalidTimestamp(){ExternalSubtitle.parse("00:99:00 --> 00:99:10\nx".toByteArray())}
 @Test(expected=IllegalArgumentException::class) fun oversized(){ExternalSubtitle.parse(ByteArray(ExternalSubtitle.MAX_BYTES+1))}

 @Test fun traditionalChineseBig5CanBeRestoredWithoutChangingTheMovie() {
  val input="1\n00:00:01,000 --> 00:00:02,500\n繁體中文字幕，這是測試！"
  val source=input.toByteArray(charset("Big5"))
  assertEquals("繁體中文字幕，這是測試！",ExternalSubtitle.parse(source,"Big5").textAt(1500))
 }
 @Test fun koreanEucKrCanBeForcedOnLegacySubtitles() {
  val input="1\n00:00:01,000 --> 00:00:02,500\n안녕하세요 반갑습니다"
  assertEquals("안녕하세요 반갑습니다",ExternalSubtitle.parse(input.toByteArray(charset("EUC-KR")),"EUC-KR").textAt(1500))
 }
 @Test fun utf16WithoutBomAndUtf8BomRemainReadable() {
  val input="1\n00:00:01,000 --> 00:00:02,500\n简体中文字幕"
  assertEquals("简体中文字幕",ExternalSubtitle.parse(input.toByteArray(Charsets.UTF_16LE)).textAt(1500))
  assertEquals("简体中文字幕",ExternalSubtitle.parse(byteArrayOf(-17,-69,-65)+input.toByteArray(Charsets.UTF_8)).textAt(1500))
 }
 @Test(expected=IllegalArgumentException::class) fun rejectUnknownForcedEncoding() {
  ExternalSubtitle.parse("1\n00:00:01,000 --> 00:00:02,500\nHi".toByteArray(),"X-UNSAFE")
 }
}
