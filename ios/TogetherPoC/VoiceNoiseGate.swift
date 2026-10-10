import Foundation

struct VoiceNoiseGate {
 let threshold:Double
 private var openUntil=0.0
 init(threshold:Double) {self.threshold=threshold}
 mutating func accepts(rms:Double,now:Double)->Bool {
  if rms.isFinite && rms >= threshold {openUntil=now+0.2}
  return now<openUntil
 }
}

/// Keeps the latest hypothesis even when Apple's final callback is blank or fails.
/// A final segment commits once; subsequent hypotheses belong to the next segment.
struct VoiceRecognitionDraft {
 private var committed:[String]=[]
 private var current=""
 private var currentStart:TimeInterval?
 private var currentEnd:TimeInterval?
 var text:String {(committed+[current]).filter {!$0.isEmpty}.joined(separator:" ")}
 mutating func accept(_ value:String,final:Bool,start:TimeInterval?=nil,end:TimeInterval?=nil) {
  let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines)
  // Apple may start a new transcription window after silence without marking
  // the previous result final. A later non-overlapping audio window is a new
  // segment; edits within the same window remain replacements, not appends.
  if !trimmed.isEmpty,!current.isEmpty,let start=start,let previousStart=currentStart,
     let previousEnd=currentEnd,start>=previousEnd,start>previousStart {
   committed.append(current);current="";currentStart=nil;currentEnd=nil
  }
  if !trimmed.isEmpty {current=trimmed}
  if !trimmed.isEmpty,let start=start,let end=end,start.isFinite,end.isFinite,end>=start {
   currentStart=start;currentEnd=end
  }
  if final,!current.isEmpty {committed.append(current);current="";currentStart=nil;currentEnd=nil}
 }
}
