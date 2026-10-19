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
  var visual: [PlotEvidence] = []
  for index in 0..<4 {
   let start = Double(8 + index * 18)
   let label = index.isMultiple(of:2) ? "室内环境" : "户外环境"
   visual.append(PlotEvidence.cue(start:start,end:start+1,
    text:label,source:"ondevice-vision"))
  }
  XCTAssertTrue(PlotQuestionPlanner.hasWatchedEvidence(visual,at:75))
  XCTAssertFalse(PlotQuestionPlanner.hasWatchedEvidence(visual.map {
   PlotEvidence.cue(start:$0.start,end:$0.end,text:"静止室内",source:"ondevice-vision")
  },at:75),"Generic unchanging picture labels are not enough")
 }
 func testAutoQuestionsRequireVisibleDetailsFromCitedSubtitle() {
  let a=PlotEvidence.cue(start:100,end:102,text:"他昨晚声称自己在家",source:"embedded-subtitle")
  let b=PlotEvidence.cue(start:106,end:108,text:"警方找到了监控录像",source:"embedded-subtitle")
  let c=PlotEvidence.cue(start:112,end:114,text:"监控记录与之前的证词存在矛盾",source:"embedded-subtitle")
  let context=PlotContext(cutoff:120,recent:[a,b,c],earlier:[],predictions:[])
  let factual=PlotQuestion(text:"警方发现监控后，为什么证词会与录像矛盾？",choices:["故意隐瞒","误会"],source:"Apple 设备端 AI",evidenceIDs:[b.id,c.id])
  XCTAssertTrue(PlotMomentGate.questionIsTimely(factual,context:context))
  let generic=PlotQuestion(text:"你觉得这个人的未来会发生什么？",choices:["成功","失败"],source:"Apple 设备端 AI",evidenceIDs:[b.id,c.id])
  XCTAssertFalse(PlotMomentGate.questionIsTimely(generic,context:context),
   "Valid-looking evidence IDs must not approve a disconnected generic question")
  let historical=PlotQuestion(text:"昨晚他为什么声称自己在家？",choices:["想隐瞒","没记清"],source:"Apple 设备端 AI",evidenceIDs:[a.id])
  XCTAssertTrue(PlotMomentGate.questionIsTimely(historical,context:context))
  XCTAssertFalse(PlotMomentGate.questionIsTimely(PlotQuestion(text:"录像是真的吗？",choices:["是","否"],source:"Apple 设备端 AI",evidenceIDs:["future-not-watched"]),context:context))
 }
  func testFullFilmPreanalysisNeverIncludesLaterDialogueInEarlierQuestionPrompt() {
  let document=SubtitleDocument([
   SubtitleCue(start:80,end:84,text:"他声称一整晚都在家"),
   SubtitleCue(start:90,end:94,text:"警方现在找到了监控录像"),
   SubtitleCue(start:98,end:102,text:"他们怀疑之前的证词"),
   SubtitleCue(start:800,end:804,text:"未来揭示的真实身份和结局"),
   SubtitleCue(start:810,end:814,text:"那个角色已经被确认是最终幕后主使")
  ])
  let early=PlotFullFilmPlanner.context(document,at:110,source:"embedded-subtitle")
  XCTAssertEqual(early.recent.count,3)
  XCTAssertFalse(early.localInput.contains("未来揭示"))
  XCTAssertFalse(early.boundedInput.contains("最终幕后主使"))
  let later=PlotFullFilmPlanner.context(document,at:820,source:"embedded-subtitle")
  XCTAssertTrue(later.recent.contains(where:{$0.text.contains("未来揭示")}),
   "Later dialogue may be used only in questions prepared for later checkpoints")
  XCTAssertEqual(PlotFullFilmPlanner.context(document,at:.nan,source:"external-subtitle").recent.count,0)
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
