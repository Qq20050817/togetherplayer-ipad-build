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
