import Foundation

/// Cheap, conservative candidate filter. It NEVER schedules questions every
/// N minutes: it only observes completed *actually played* subtitle evidence.
struct PlotStoryBeatDetector {
 static let cueWords=["为什么","怎么会","真的吗","不可能","秘密","瞒","隐瞒","骗","说谎","真相","证据","失踪","是谁","到底","发现","原来","但是","可是","却","如果","警方","照片","钥匙","昨晚","之前","记得","矛盾","怀疑","恐怕","可疑","没去过","杀人"]
 static func candidate(context:PlotContext,position:Double,lastAsked:Double?,questionCount:Int)->Bool {
  // Time is used only to avoid interrupting active scenes and excessive
  // interruptions, NEVER as a "ask every 20 minutes" trigger.
  guard questionCount<6,position.isFinite,position>=120 else{return false}
  guard lastAsked.map({position-$0>=240}) ?? true else{return false}
  let cues=Array(context.recent.suffix(14))
  guard cues.count>=6,let last=cues.last else{return false}
  let pause=position-last.end
  guard pause>=3.5 && pause<=16 && last.end>=cues[0].start else{return false}
  let active=cues.filter{$0.end>=last.end-140}
  guard active.count>=6,Set(active.map(\.id)).count>=6 else{return false}
  // A pause after ordinary small talk does not qualify. Signs merely
  // nominate a possible beat; the on-device AI must judge its importance.
  let weighted=active.suffix(9).reduce(0){sum,cue in
   let matches=cueWords.filter{cue.text.contains($0)}.count
   return sum+min(2,matches)+(cue.text.contains("？") || cue.text.contains("?") ? 1:0)
  }
  return weighted>=3
 }
}
