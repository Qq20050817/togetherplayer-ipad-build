import Foundation
import CoreFoundation

struct SubtitleCue: Equatable {
 let start: Double
 let end: Double
 let text: String
}
struct SubtitleDocument {
 let cues: [SubtitleCue]
 private let maximumEnds: [Double]
 init(_ cues: [SubtitleCue]) {
  self.cues=cues.sorted { $0.start < $1.start }
  var ends: [Double]=[];var maximum=0.0
  for cue in self.cues {maximum=max(maximum,cue.end);ends.append(maximum)}
  maximumEnds=ends
 }
 func text(at time: Double) -> String {
  guard time.isFinite,!cues.isEmpty else {return ""}
  var low=0;var high=cues.count
  while low<high {let mid=(low+high)/2;if cues[mid].start<=time {low=mid+1} else {high=mid}}
  var index=low-1;var active: [String]=[]
  while index>=0,maximumEnds[index]>time {
   let cue=cues[index];if cue.start<=time && time<cue.end {active.append(cue.text)}
   index-=1
  }
  return active.reversed().joined(separator:"\n")
 }
}
enum SubtitleParseError: Error, Equatable {case size,encoding,noCues}
enum SubtitleParser {
 static let maxBytes=5*1024*1024
 static func parse(_ data: Data,extension ext: String) throws -> SubtitleDocument {
  guard data.count<=maxBytes else {throw SubtitleParseError.size}
  let gb=String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
  let utf16BOM=data.starts(with:[0xff,0xfe]) || data.starts(with:[0xfe,0xff])
  let decoded=utf16BOM ? String(data:data,encoding:.utf16) : (String(data:data,encoding:.utf8) ?? String(data:data,encoding:gb))
  guard var source=decoded else {throw SubtitleParseError.encoding}
  source=source.replacingOccurrences(of:"\u{feff}",with:"").replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
  let cues=(ext.lowercased()=="ass" || ext.lowercased()=="ssa") ? ass(source) : timedText(source)
  guard !cues.isEmpty else {throw SubtitleParseError.noCues}
  return SubtitleDocument(cues)
 }
 static func timestamp(_ source: String) -> Double? {
  let parts=source.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:",",with:".").split(separator:":")
  guard parts.count==2 || parts.count==3,let seconds=Double(parts.last!),seconds>=0,seconds<60,
   let minutes=Double(parts[parts.count-2]),minutes>=0,minutes<60 else {return nil}
  let hours=parts.count==3 ? Double(parts[0]) : 0
  guard let hours=hours,hours>=0 else {return nil}
  let value=hours*3600+minutes*60+seconds
  return value.isFinite ? value : nil
 }
 private static func timedText(_ source: String) -> [SubtitleCue] {
  let lines=source.components(separatedBy:"\n");var cues: [SubtitleCue]=[];var i=0
  while i<lines.count {
   let line=lines[i];i+=1
   let header=line.trimmingCharacters(in:.whitespaces)
   if header=="NOTE" || header.hasPrefix("NOTE ") || header=="STYLE" || header=="REGION" {
    while i<lines.count,!lines[i].trimmingCharacters(in:.whitespaces).isEmpty {i+=1}
    continue
   }
   guard line.contains("-->"),!line.trimmingCharacters(in:.whitespaces).hasPrefix("NOTE") else {continue}
   let times=line.components(separatedBy:"-->")
   guard times.count==2,let endToken=times[1].split(whereSeparator:{$0.isWhitespace}).first,
    let start=timestamp(times[0]),let end=timestamp(String(endToken)),end>start else {continue}
   var text: [String]=[]
   while i<lines.count,!lines[i].trimmingCharacters(in:.whitespaces).isEmpty {text.append(lines[i]);i+=1}
   let cleaned=clean(text.joined(separator:"\n"),ass:false)
   if !cleaned.isEmpty {cues.append(SubtitleCue(start:start,end:end,text:cleaned))}
  }
  return cues
 }
 private static func ass(_ source: String) -> [SubtitleCue] {
  var events=false;var format=["layer","start","end","style","name","marginl","marginr","marginv","effect","text"];var cues: [SubtitleCue]=[]
  for raw in source.components(separatedBy:"\n") {
   let line=raw.trimmingCharacters(in:.whitespaces)
   if line.hasPrefix("[") {events=line.lowercased()=="[events]";continue}
   guard events else {continue}
   if line.lowercased().hasPrefix("format:") {format=line.dropFirst(7).split(separator:",").map {$0.trimmingCharacters(in:.whitespaces).lowercased()};continue}
   guard line.lowercased().hasPrefix("dialogue:"),let startIndex=format.firstIndex(of:"start"),let endIndex=format.firstIndex(of:"end"),let textIndex=format.firstIndex(of:"text"),textIndex==format.count-1 else {continue}
   let fields=line.dropFirst(9).split(separator:",",maxSplits:format.count-1,omittingEmptySubsequences:false)
   guard fields.count==format.count,let start=timestamp(String(fields[startIndex])),let end=timestamp(String(fields[endIndex])),end>start else {continue}
   let rawText=String(fields[textIndex])
   // Drawing commands are not dialogue; do not display their vector coordinates.
   guard rawText.range(of:#"\\p[1-9]"#,options:.regularExpression)==nil else {continue}
   let text=clean(rawText,ass:true)
   if !text.isEmpty {cues.append(SubtitleCue(start:start,end:end,text:text))}
  }
  return cues
 }
 private static func clean(_ raw: String,ass: Bool) -> String {
  var text=raw
  if ass {text=text.replacingOccurrences(of:#"\{[^}]*\}"#,with:"",options:.regularExpression).replacingOccurrences(of:#"\N"#,with:"\n").replacingOccurrences(of:#"\n"#,with:"\n").replacingOccurrences(of:#"\h"#,with:" ")}
  text=text.replacingOccurrences(of:#"<[^>]*>"#,with:"",options:.regularExpression)
  for (entity,value) in [("&lt;","<"),("&gt;",">"),("&quot;","\""),("&apos;","'"),("&nbsp;"," "),("&amp;","&")] {text=text.replacingOccurrences(of:entity,with:value)}
  return text.trimmingCharacters(in:.whitespacesAndNewlines)
 }
}
