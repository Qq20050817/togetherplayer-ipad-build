import Foundation

/// AI-only text projection of a timestamped bitmap-subtitle OCR transcript.
/// The movie container and its selected playback subtitle track are untouched.
/// OCR confidence and the original PGS bitmap are not represented by SRT.
enum SubtitleSRTEncoder {
 static func encode(_ document: SubtitleDocument) -> String {
  var records:[String]=[]
  for cue in document.cues {
   guard let start=timestamp(cue.start),let end=timestamp(cue.end),
         cue.end>cue.start else {continue}
   let cleaned=cue.text.replacingOccurrences(of:"\r\n",with:"\n")
    .replacingOccurrences(of:"\r",with:"\n")
    .trimmingCharacters(in:.whitespacesAndNewlines)
   guard !cleaned.isEmpty else {continue}
   records.append("\(records.count+1)\n\(start) --> \(end)\n\(cleaned)")
  }
  return records.isEmpty ? "" : records.joined(separator:"\n\n")+"\n"
 }
 private static func timestamp(_ value:Double)->String? {
  guard value.isFinite,value>=0,value<360000 else{return nil}
  let ms=Int((value*1000).rounded())
  return String(format:"%02d:%02d:%02d,%03d",ms/3600000,
                (ms/60000)%60,(ms/1000)%60,ms%1000)
 }
}
