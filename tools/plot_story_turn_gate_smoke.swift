import Foundation

// Isolated Linux smoke harness: production PlotMomentGate.swift is compiled
// directly, while these tiny structs stand in for the iPad application's data.
struct PlotEvidence {
 let id:String
 let start:Double
 let end:Double
 let text:String
}
struct PlotQuestion {
 let evidenceIDs:[String]
}
struct PlotContext {
 let recent:[PlotEvidence]
}
@main enum PlotStoryTurnSmoke {
 static func cue(_ end:Double,_ text:String)->PlotEvidence {
  PlotEvidence(id:"\(Int(end))",start:end-2,end:end,text:text)
 }
 static func main() {
  let suspicious=[
   cue(4,"你说昨晚一直在家，没人看见你"),
   cue(8,"我不想告诉任何人那件事"),
   cue(12,"但警方发现了另一份证据"),
   cue(16,"你刚才是不是在说谎？"),
   cue(20,"不是我，我不知道事情的真相"),
   cue(24,"那你为什么知道那个秘密？")
  ]
  precondition(PlotMomentGate.likelyQuestionMoment(suspicious,position:28),"important contradiction should trigger")
  precondition(!PlotMomentGate.likelyQuestionMoment(suspicious,position:24),"no interruption mid-dialogue")
  precondition(!PlotMomentGate.likelyQuestionMoment(suspicious,position:45),"old clue should expire")
  let routine=[
   cue(4,"今天早餐你想喝牛奶还是喝果汁？"),
   cue(8,"为什么买这件衣服，而不选择另外一件呢？"),
   cue(12,"可是这个牌子的东西最近有点贵。"),
   cue(16,"你说的价格我也不知道怎么回事。"),
   cue(20,"我想先回家再商量要买什么。"),
   cue(24,"但是我们还需要买点水果带回去。")
  ]
  precondition(!PlotMomentGate.likelyQuestionMoment(routine,position:28),"normal conversation should not trigger")
  let revelation=[
   cue(4,"他说那天晚上一直留在家里，完全没有离开过"),
   cue(8,"我们原本也以为这件事只是个误会"),
   cue(12,"警方今天查到了那晚的另一份证据"),
   cue(16,"监控录像清楚拍下一个人离开了房间"),
   cue(20,"然而这与他之前说过的话根本不一致"),
   cue(24,"现在终于发现这段证词有明显的矛盾")
  ]
  precondition(PlotMomentGate.likelyQuestionMoment(revelation,position:28),"real reveal should trigger")
  let long=(0..<12).map{cue(Double(2+$0*2),"监控发现证据之后，刚才那个人为什么隐瞒真相？")}
  precondition(!PlotMomentGate.likelyQuestionMoment(long,position:28),"dense dialogue should be skipped")
  precondition(PlotMomentGate.canAttempt(position:700,lastAttempt:100,lastPublished:100))
  precondition(!PlotMomentGate.canAttempt(position:630,lastAttempt:100,lastPublished:100))
  let context=PlotContext(recent:revelation)
  precondition(PlotMomentGate.questionIsTimely(PlotQuestion(evidenceIDs:[revelation[5].id]),context:context))
  precondition(!PlotMomentGate.questionIsTimely(PlotQuestion(evidenceIDs:["future-id"]),context:context))
  print("PASS: plot story-turn gate compiles; reveal, mundane dialogue, timing, cooldown and citation checks passed")
 }
}
