import Foundation
import CoreFoundation

@main struct SubtitleParserRegression {
 static func main() throws {
  let srt="1\r\n00:00:01,000 --> 00:00:03,000\r\n<b>你好</b>\r\n第二行\r\n\r\n2\r\n00:00:02,000 --> 00:00:04,000\r\n重叠字幕\r\n"
  let doc=try SubtitleParser.parse(Data(srt.utf8),extension:"srt")
  precondition(doc.text(at:0).isEmpty)
  precondition(doc.text(at:1)=="你好\n第二行")
  precondition(doc.text(at:2)=="你好\n第二行\n重叠字幕")
  precondition(doc.text(at:3)=="重叠字幕")
  precondition(doc.text(at:4).isEmpty)
  // Queries are independent of previous playback position: seek backwards works.
  precondition(doc.text(at:1)=="你好\n第二行")
  let vtt="WEBVTT\n\nNOTE ignored\n00:00:00.000 --> 00:00:10.000\nDo not display\n\ncue-id\n00:01.500 --> 00:02.500 align:center\n<v Speaker>Hello &amp; goodbye</v>\n"
  let web=try SubtitleParser.parse(Data(vtt.utf8),extension:"vtt")
  precondition(web.cues.count==1 && web.text(at:2)=="Hello & goodbye")
  let ass="[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\i1}你好\\N世界, with comma\nDialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\p1}m 0 0 l 20 20\n"
  let styled=try SubtitleParser.parse(Data(ass.utf8),extension:"ass")
  precondition(styled.cues.count==1 && styled.text(at:2)=="你好\n世界, with comma")
  let utf16=srt.data(using:.utf16)!
  let unicode=try SubtitleParser.parse(utf16,extension:"srt")
  precondition(unicode.text(at:1)=="你好\n第二行")
  let gb=String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
  let chinese=try SubtitleParser.parse(srt.data(using:gb)!,extension:"srt")
  precondition(chinese.text(at:1)=="你好\n第二行")
  do { _=try SubtitleParser.parse(Data("bad subtitle".utf8),extension:"srt");preconditionFailure("Malformed file accepted") } catch SubtitleParseError.noCues {}
  do { _=try SubtitleParser.parse(Data(repeating:0,count:SubtitleParser.maxBytes+1),extension:"srt");preconditionFailure("Oversized file accepted") } catch SubtitleParseError.size {}
  precondition(SubtitleParser.timestamp("00:60:00.000")==nil)
  // Positive delay shows the cue later, without changing the movie timeline.
  precondition(doc.text(at:1.5-1).isEmpty && doc.text(at:2-1)=="你好\n第二行")
  print("PASS: subtitle timing, overlapping cues, backward seek, VTT notes/settings, ASS text, UTF16/GB18030, size and malformed input")
 }
}
