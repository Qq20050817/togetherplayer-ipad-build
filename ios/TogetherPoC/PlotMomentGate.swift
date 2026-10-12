import Foundation

/// Subtitle-only signals for a possible important story turn. These numbers are
/// conservative routing heuristics, NOT a factual understanding of the scene.
struct PlotBeatAssessment: Equatable {
 let informationChange:Int
 let contradiction:Int
 let unresolvedMystery:Int
 let dialogueBreak:Bool
 let evidenceIDs:[String]
 var importance:Int {min(100,informationChange*15+contradiction*15+unresolvedMystery*10)}
 var isCandidate:Bool {
  dialogueBreak && importance>=65 &&
  ((informationChange>=2 && (contradiction>=1 || unresolvedMystery>=2)) ||
   (contradiction>=2 && unresolvedMystery>=2))
 }
}

enum PlotMomentGate {
 // Require multiple *different* narrative indicators. Everyday questions,
 // isolated "but", and fixed movie timestamps do not request an AI call.
 static let discoveries=["原来","其实","真正","发现","查到","证实","证明","揭露","曝光","监控","证据","线索","真相","秘密","身份","找到","认出","录像","录音","尸体","凶器","警方","调查","报告","失踪","另一份","另一人","另一种","revealed","discovered","evidence","secret","identity","truth","recording"]
 static let reversals=["但是","可是","然而","却","明明","不可能","根本","不是我","不是他","不是她","没有","从没","从未","撒谎","说谎","骗了","隐瞒","矛盾","不对","相反","but ","however","impossible","lied","lying","contradict","never"]
 static let questions=["为什么","怎么知道","怎么会","究竟","难道","到底","是谁","谁才","怀疑","凶手","不明白","不可思议","可疑","？","?","why","how did","who","suspect","murder"]
 static let contextLinks=["之前","刚才","昨晚","那天","当时","一直","你说","我说","还记得","本来","原以为","早就","先前","当初","昨天","之前说过","earlier","yesterday","last night","before"]

 private static func matchCount(_ text:String,against words:[String])->Int {
  words.reduce(0){$0+(text.contains($1) ? 1 : 0)}
 }
 static func assess(_ values:[PlotEvidence],position:Double,minQuietSeconds:Double=1.8)->PlotBeatAssessment {
  let empty=PlotBeatAssessment(informationChange:0,contradiction:0,unresolvedMystery:0,dialogueBreak:false,evidenceIDs:[])
  guard position.isFinite,position>=0 else{return empty}
  // A cue is eligible only after its end and only if it belongs to this
  // actually watched 95-second window. Never read an unplayed future cue.
  let recent=Array(values.filter{$0.start>=0 && $0.end.isFinite && $0.end<=position && $0.end>=position-95}.suffix(16))
  guard recent.count>=5,let last=recent.last else{return empty}
  let gap=position-last.end
  guard gap>=minQuietSeconds,gap<=16 else{return empty}
  let latest=Array(recent.suffix(5))
  guard latest.map(\.text).joined().count>=35 else{return empty}
  // Avoid interrupting rapid-fire scenes at tiny subtitle gaps.
  let nearbyCount=recent.filter{$0.end>=position-30}.count
  guard nearbyCount<=10 else{return empty}
  let latestText=latest.map(\.text).joined(separator:" ").lowercased()
  let earlierText=recent.dropLast(5).map(\.text).joined(separator:" ").lowercased()
  let discoveryCount=matchCount(latestText,against:discoveries)
  let reversalCount=matchCount(latestText,against:reversals)
  let mysteryCount=matchCount(latestText,against:questions)
  let prior=matchCount(earlierText+" "+latestText,against:contextLinks)>0
  // Contradictions need an actual reversal plus prior statements or a
  // stronger denial; a standalone "but" should not pause a film.
  let contradiction=min(3,reversalCount+(prior && reversalCount>0 ? 1 : 0))
  let information=min(3,discoveryCount)
  let mystery=min(3,mysteryCount)
  return PlotBeatAssessment(informationChange:information,contradiction:contradiction,
   unresolvedMystery:mystery,dialogueBreak:true,evidenceIDs:latest.map(\.id))
 }
 static func likelyQuestionMoment(_ values:[PlotEvidence],position:Double,minQuietSeconds:Double=1.8)->Bool {
  assess(values,position:position,minQuietSeconds:minQuietSeconds).isCandidate
 }
 static func questionIsTimely(_ question:PlotQuestion,context:PlotContext)->Bool {
  let recentIDs=Set(context.recent.suffix(8).map(\.id))
  return !question.evidenceIDs.isEmpty && !recentIDs.isDisjoint(with:question.evidenceIDs)
 }
}
