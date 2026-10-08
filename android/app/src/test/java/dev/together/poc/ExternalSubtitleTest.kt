package dev.together.poc
import org.junit.Assert.*
import org.junit.Test
class ExternalSubtitleTest {
 @Test fun overlappingCuesAndBackwardSeek(){val s=ExternalSubtitle.parse("1\n00:00:01,000 --> 00:00:03,000\n你好\n\n2\n00:00:02,000 --> 00:00:04,000\nWorld".toByteArray());assertEquals("你好\nWorld",s.textAt(2500));assertEquals("World",s.textAt(3000));assertEquals("你好",s.textAt(1500));assertEquals("",s.textAt(1500,1000))}
 @Test fun assTextAndDrawing(){val s=ExternalSubtitle.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:03.00,{\\i1}a,b\\N你好\nDialogue: 0,0:00:01.00,0:00:03.00,{\\p1}m 0 0".toByteArray());assertEquals("a,b\n你好",s.textAt(2000))}
 @Test fun vttAndEncoding(){val input="WEBVTT\n\nNOTE ignore\n\n1\n00:01.000 --> 00:02.000 align:start\n中文";assertEquals("中文",ExternalSubtitle.parse(input.toByteArray(charset("GB18030"))).textAt(1500));val bytes=byteArrayOf(-1,-2)+input.toByteArray(Charsets.UTF_16LE);assertEquals("中文",ExternalSubtitle.parse(bytes).textAt(1500))}
 @Test(expected=IllegalArgumentException::class) fun invalidTimestamp(){ExternalSubtitle.parse("00:99:00 --> 00:99:10\nx".toByteArray())}
 @Test(expected=IllegalArgumentException::class) fun oversized(){ExternalSubtitle.parse(ByteArray(ExternalSubtitle.MAX_BYTES+1))}
}
