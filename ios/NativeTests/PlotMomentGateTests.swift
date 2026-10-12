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
 func testFutureDialogueAndFreshSceneDoNotTrigger() {
  let future=suspicious.map{PlotEvidence.cue(start:$0.start+100,end:$0.end+100,text:$0.text,source:$0.source)}
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(future,position:24))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:24.7))
  XCTAssertFalse(PlotMomentGate.likelyQuestionMoment(suspicious,position:Double.nan))
 }
}
