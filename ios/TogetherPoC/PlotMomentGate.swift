import Foundation

/// Cheap, evidence-only trigger gate. It never schedules questions at fixed
/// movie positions and never reads unplayed subtitle cues.
enum PlotMomentGate {
 static let signalWords=[
  "为什么","怎么会","怎么知道","不可能","但是","可是","然而","撒谎","说谎","骗了","隐瞒","真相","秘密","证据","线索","矛盾","怀疑","凶手","杀人","失踪","不见了","昨晚","那天","记得","忘记","不是我","谁","骗","难道",
  "why","how did","who","but ","however","lie","lying","secret","truth","evidence","murder","missing","suspect","remember","impossible"
 ]
 static func likelyQuestionMoment(_ values:[PlotEvidence],position:Double,minQuietSeconds:Double=1.8)->Bool {
  guard position.isFinite,position>=0 else{return false}
  let current=Array(values.filter{$0.end<=position && $0.end>=position-95}.suffix(16))
  guard current.count>=5,let last=current.last,position-last.end>=minQuietSeconds,
   position-last.end<=16 else{return false}
  let latest=Array(current.suffix(5))
  guard latest.map(\.text).joined().count>=35 else{return false}
  let combined=latest.map(\.text).joined(separator:" ").lowercased()
  let strong=signalWords.filter{combined.contains($0)}.count
  let interrogative=combined.contains("？") || combined.contains("?")
  // A single conversational "why?" isn't enough. Require several actual
  // completed subtitle cues and at least one strong story signal.
  return strong>=2 || (strong>=1 && interrogative && latest.count>=4)
 }
}
