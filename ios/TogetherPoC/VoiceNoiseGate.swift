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
 var text:String {(committed+[current]).filter {!$0.isEmpty}.joined(separator:" ")}
 mutating func accept(_ value:String,final:Bool) {
  let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines)
  if !trimmed.isEmpty {current=trimmed}
  if final,!current.isEmpty {committed.append(current);current=""}
 }
}
