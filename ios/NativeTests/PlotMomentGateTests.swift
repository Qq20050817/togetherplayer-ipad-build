import XCTest
@testable import TogetherPoC

final class PlotMomentGateTests:XCTestCase {
 private func cue(_ end:Double,_ text:String)->PlotEvidence {
  PlotEvidence.cue(start:end-2,end:end,text:text,source:"already-watched")
 }
 private var suspicious:[PlotEvidence] {[
  cue(4,"你说昨晚一直在家，没人看见你"),
  cue(8,"我不想告诉任何人那件事"),
  cue(12,"但警方发现了另一份证据"),
  cue(16,"你刚才是不是在说谎？"),
  cue(20,"不是我，我不知道事情的真相"),
  cue(24,"那你为什么知道那个秘密？")
 ]}
 func testSuspiciousMomentOnlyAfterDialogueGap() {
  XCTAssertTrue(PlotMomentGate.likelyQuestionMoment(suspicious,position:24,minQuietSeconds:0))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:24))
  XCTAssertTrue(PlotMomentGate.likelyQuestionMoment(suspicious,position:28))
 }
 func testNoBlindFixedMinutePromptAndNoRoutineDialogue() {
  let normal=[
   cue(4,"我今天去商店买了一些新的生活用品。"),
   cue(8,"这些物品的数量很多，我准备慢慢收拾。"),
   cue(12,"昨天我们见到了朋友，聊了很长时间。"),
   cue(16,"然后大家一起吃饭，看了几场表演。"),
   cue(20,"我想等到明天早上再整理房间。")
  ]
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(normal,position:26))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:120))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment([],position:3600))
 }
 func testRevelationWithOldAlibiAndNewRecordingTriggersWithoutQuestionMark() {
  let clues=[
   cue(4,"他说那天晚上一直留在家里，完全没有离开过"),
   cue(8,"我们原本也以为这件事只是个误会"),
   cue(12,"警方今天查到了那晚的另一份证据"),
   cue(16,"监控录像清楚拍下一个人离开了房间"),
   cue(20,"然而这与他之前说过的话根本不一致"),
   cue(24,"现在终于发现这段证词有明显的矛盾")
  ]
  let signal=PlotMomentGate.assess(clues,position:28)
  XCTAssertTrue(signal.isCandidate)
  XCTAssertGreaterThanOrEqual(signal.informationChange,2)
  XCTAssertGreaterThanOrEqual(signal.contradiction,1)
  XCTAssertTrue(PlotMomentGate.likelyQuestionMoment(clues,position:28))
 }
 func testSmallTalkAndQuestionsWithoutNewPlotEvidenceNeverInterrupt() {
  let routine=[
   cue(4,"今天早餐你想喝牛奶还是喝果汁？"),
   cue(8,"为什么买这件衣服，而不选择另外一件呢？"),
   cue(12,"可是这个牌子的东西最近有点贵。"),
   cue(16,"你说的价格我也不知道怎么回事。"),
   cue(20,"我想先回家再商量要买什么。"),
   cue(24,"但是我们还需要买点水果带回去。")
  ]
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(routine,position:28))
  let isolated=[
   cue(4,"大家在客厅等了很久"),cue(8,"他刚才出门买了点东西"),
   cue(12,"今天有人到访"),cue(16,"我们刚刚发现一封信"),
   cue(20,"其他人都点了点头"),cue(24,"所以大家继续聊天")
  ]
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(isolated,position:28))
 }
 func testImportantQuestionMustCiteFreshSubtitleEvidence() {
  let values=(0..<12).map{cue(Double(4+$0*4),"关于那天的真相我们仍有一些疑问和没有解释的地方")}
  let context=PlotContext(cutoff:60,recent:values,earlier:[],predictions:[])
  let old=PlotQuestion(text:"这两种线索如何解释？",choices:["一","二"],source:"ChatGPT",evidenceIDs:[values[0].id])
  let fresh=PlotQuestion(text:"新发现的线索意味着什么？",choices:["一","二"],source:"ChatGPT",evidenceIDs:[values[11].id])
  XCTAssertFalse(PlotMomentGate.questionIsTimely(old,context:context))
  XCTAssertTrue(PlotMomentGate.questionIsTimely(fresh,context:context))
 }
 func testRapidDialogueAndPastMomentDoNotInterrupt() {
  let dense=(0..<12).map{cue(Double(2+$0*2),"监控发现证据之后，刚才那个人为什么隐瞒真相？")}
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(dense,position:28),"rapid dialogue should not be interrupted")
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:45),"old moments expire")
 }
  func testFutureDialogueAndFreshSceneDoNotTrigger() {
  let future=suspicious.map{PlotEvidence.cue(start:$0.start+100,end:$0.end+100,text:$0.text,source:$0.source)}
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(future,position:24))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:24.7))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:Double.nan))
 }
}
