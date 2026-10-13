import XCTest
@testable import TogetherPoC

final class PlotQuestionPlannerTests:XCTestCase {
 private func subtitle(_ start:Double,_ text:String)->SubtitleCue {
  SubtitleCue(start:start,end:start+3,text:text)
 }
 func testFullSubtitleIndexCreatesActualSceneRegionsNotBlindMinuteTimers() {
  var cues:[SubtitleCue]=[]
  for i in 0..<26 {
   let text=i.isMultiple(of:3) ? "警方发现新的证据，然而之前的说法有明显矛盾" :
    "我们刚才调查的线索为什么和之前发现的记录不一致"
   cues.append(subtitle(280+Double(i)*16,text))
  }
  let points=PlotQuestionPlanner.indexed(cues)
  XCTAssertFalse(points.isEmpty)
  XCTAssertLessThanOrEqual(points.count,8)
  XCTAssertTrue(points.allSatisfy{$0.at>=120 && $0.at<cues.last!.end && $0.score>0})
  XCTAssertEqual(points,points.sorted{$0.at<$1.at})
  let first=try? XCTUnwrap(points.first)
  XCTAssertNotNil(first)
  if let first {
   XCTAssertNil(PlotQuestionPlanner.active(points,at:first.at-0.1),
    "No future question checkpoint can trigger early")
   XCTAssertEqual(PlotQuestionPlanner.active(points,at:first.at+15),first.at)
   XCTAssertNil(PlotQuestionPlanner.active(points,at:first.at+56),
    "A stale checkpoint must not interrupt long after its story window")
  }
 }
 func testNativeDurationWindowsAreOnlyCandidatesAndUnknownDurationDoesNotFabricateScenes() {
  XCTAssertTrue(PlotQuestionPlanner.durationCheckpoints(.nan).isEmpty)
  XCTAssertTrue(PlotQuestionPlanner.durationCheckpoints(0).isEmpty)
  let milestones=PlotQuestionPlanner.durationCheckpoints(5400)
  XCTAssertGreaterThanOrEqual(milestones.count,5)
  XCTAssertTrue(milestones.allSatisfy{$0.score==0})
  XCTAssertNil(PlotQuestionPlanner.active(milestones,at:10))
  let first=milestones[0].at
  XCTAssertEqual(PlotQuestionPlanner.active(milestones,at:first+10),first)
 }
 func testScheduledTriggerRequiresOnlyAlreadyWatchedEvidence() {
  let played=[
   PlotEvidence.cue(start:100,end:102,text:"他昨晚说自己在家",source:"embedded-subtitle"),
   PlotEvidence.cue(start:108,end:110,text:"刚才警方发现新的线索",source:"embedded-subtitle"),
   PlotEvidence.cue(start:116,end:118,text:"这和之前的证词存在明显矛盾",source:"embedded-subtitle")
  ]
  XCTAssertTrue(PlotQuestionPlanner.hasWatchedEvidence(played,at:128))
  XCTAssertFalse(PlotQuestionPlanner.hasWatchedEvidence(Array(played.prefix(2)),at:128))
  XCTAssertFalse(PlotQuestionPlanner.hasWatchedEvidence(played,at:104),
   "Do not accept clues from a later, unplayed scene")
  XCTAssertFalse(PlotQuestionPlanner.hasWatchedEvidence(played,at:400),
   "Old dialogue must not provoke an unrelated interruption")
  let visual=(0..<4).map {index in
   PlotEvidence.cue(start:Double(8+index*18),end:Double(9+index*18),
    text:index.isMultiple(of:2) ? "室内环境" : "户外环境",source:"ondevice-vision")
  }
  XCTAssertTrue(PlotQuestionPlanner.hasWatchedEvidence(visual,at:75))
  XCTAssertFalse(PlotQuestionPlanner.hasWatchedEvidence(visual.map {
   PlotEvidence.cue(start:$0.start,end:$0.end,text:"静止室内",source:"ondevice-vision")
  },at:75),"Generic unchanging picture labels are not enough")
 }
 func testNoWholeFilmTranscriptLeaksIntoPromptMemory() {
  let values=[
   PlotEvidence.cue(start:2,end:5,text:"开场已经看过的故事",source:"external-subtitle"),
   PlotEvidence.cue(start:900,end:905,text:"秘密的未来结局绝不能提前显示",source:"external-subtitle")
  ]
  var state=PlotMemoryState()
  state.ingest(values,cutoff:30)
  XCTAssertFalse(state.context(at:30).input.contains("未来结局"))
  XCTAssertEqual(state.evidence.count,1)
 }
}
