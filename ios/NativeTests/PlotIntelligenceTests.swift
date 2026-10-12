import XCTest
@testable import TogetherPoC

final class PlotMemoryTests:XCTestCase {
 func testThreeRealFilmSubtitleReplaysExcludeFutureAndReuseWithoutCloud() throws {
  struct Replay:Decodable {let films:[Film]}
  struct Film:Decodable {let title:String;let sample:[Cue]}
  struct Cue:Decodable {let start:Double;let end:Double;let text:String}
  let bundle=Bundle(for:Self.self)
  let url=try XCTUnwrap(bundle.url(forResource:"PlotFilmReplay",withExtension:"json"))
  let replay=try JSONDecoder().decode(Replay.self,from:Data(contentsOf:url))
  XCTAssertEqual(replay.films.count,3)
  for film in replay.films {
   let values=film.sample.map{PlotEvidence.cue(start:$0.start,end:$0.end,text:$0.text,source:film.title)}
   var memory=PlotMemoryState();memory.ingest(values,cutoff:1200)
   XCTAssertTrue(memory.evidence.allSatisfy{$0.end<=1200});XCTAssertLessThan(memory.evidence.count,values.count)
   let context=memory.context(at:1200)
   XCTAssertTrue(context.recent.allSatisfy{$0.end<=1200})
   XCTAssertLessThanOrEqual(context.boundedInput.count,9500)
   let question=PlotFallback.question(context:context,history:[])
   XCTAssertTrue(PlotQuality.check(question,context:context,history:[],allowGeneric:true))
   memory.remember(question,at:1200);XCTAssertEqual(memory.reusable(at:1201),question)
   XCTAssertEqual(memory.budget.total,0)
   XCTAssertTrue(memory.context(at:300).recent.allSatisfy{$0.end<=300})
  }
 }
 func evidence(_ start:Double,_ text:String)->PlotEvidence {PlotEvidence.cue(start:start,end:start+2,text:text,source:"test")}
 func testFutureAndOpenCuesCannotEnterMemory() {
  var memory=PlotMemoryState();let past=evidence(5,"已看"),future=evidence(20,"未来")
  memory.ingest([past,future],cutoff:10)
  XCTAssertEqual(memory.evidence,[past]);XCTAssertFalse(memory.context(at:10).input.contains("未来"))
 }
 func testBackwardSeekExcludesLaterCluesPredictionsAndCachedQuestions() {
  var memory=PlotMemoryState();let a=evidence(5,"较早"),b=evidence(50,"之后")
  memory.ingest([a,b],cutoff:100)
  memory.clues=[PlotClue(id:"clue",kind:"inference",text:"之后的猜测",evidenceIDs:[b.id],end:52,confidence:0.8)]
  memory.predictions=[PlotPrediction(id:"poll",end:60,question:"之后的问题",answers:["u":"秘密"])]
  memory.remember(PlotQuestion(text:"之后的问题",choices:["一","二"],source:"test"),at:60)
  let rewound=memory.context(at:10)
  XCTAssertEqual(rewound.recent,[a]);XCTAssertTrue(rewound.earlier.isEmpty);XCTAssertTrue(rewound.predictions.isEmpty)
  XCTAssertNil(memory.reusable(at:10));XCTAssertFalse(rewound.input.contains("秘密"))
 }
 func testSummariesNeedActualEvidenceAndNeverBecomeFacts() {
  var memory=PlotMemoryState();let a=evidence(5,"我没看见他")
  memory.ingest([a],cutoff:10);let context=memory.context(at:10)
  memory.addClues([PlotClue(id:"bad",kind:"inference",text:"无证据",evidenceIDs:["missing"],end:9,confidence:1)],context:context)
  XCTAssertTrue(memory.clues.isEmpty)
  XCTAssertEqual(memory.context(at:800).earlier.first?.kind,"quote")
 }
 func testBudgetCountsDispatchesAndPreventsLoops() {
  var budget=PlotBudget()
  for i in 0..<10 {XCTAssertTrue(budget.reserve(segment:i,now:1000+Double(i)*180,manualRequest:false))}
  XCTAssertFalse(budget.reserve(segment:11,now:5000,manualRequest:false));XCTAssertEqual(budget.automatic,10)
  XCTAssertTrue(budget.reserve(segment:11,now:5000,manualRequest:true));XCTAssertEqual(budget.total,11)
  XCTAssertFalse(budget.reserve(segment:12,now:5001,manualRequest:true))
  budget.failedSegments.insert(12);XCTAssertFalse(budget.reserve(segment:12,now:5500,manualRequest:false,limit:50))
 }
 func testSameSegmentCacheCannotBeReusedBeforeItsEvidence() {
  var state=PlotMemoryState();let q=PlotQuestion(text:"现在的问题是什么？",choices:["一","二"],source:"test")
  state.remember(q,at:65);XCTAssertEqual(state.reusable(at:80),q);XCTAssertNil(state.reusable(at:60));XCTAssertNil(state.reusable(at:185))
 }
 func testStorePersistsBudgetAndUsesIsolatedFilmKeys() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let store=PlotMemoryStore(directory:root),key=PlotMemoryStore.key("film A")
  let reserved=try await store.reserve(key:key,segment:0,manual:false,limit:10,interval:180,now:1000);XCTAssertTrue(reserved)
  let restored=await PlotMemoryStore(directory:root).load(key)
  XCTAssertEqual(restored.budget.automatic,1)
  let other=await store.load(PlotMemoryStore.key("film B"));XCTAssertEqual(other.budget.automatic,0)
 }
 func testAuthenticationRequiresTwoSameLaunchCallsAndSuccessfulRestart() {
  var check=PlotAuthAcceptance();check.success(run:"first");XCTAssertFalse(check.ready)
  check.success(run:"first");XCTAssertFalse(check.ready)
  check.success(run:"second");XCTAssertTrue(check.ready)
  var interrupted=PlotAuthAcceptance();interrupted.success(run:"first");interrupted.success(run:"second");XCTAssertFalse(interrupted.ready)
 }
 func testQualityRejectsUncitedSpoilersDuplicateOptionsAndRepeatedQuestions() {
  let values=[evidence(1,"我在车站"),evidence(4,"你之前说在家"),evidence(7,"也许记错了")]
  let context=PlotContext(cutoff:10,recent:values,earlier:[],predictions:[])
  var q=PlotQuestion(text:"这两种说法为什么有差异？",choices:["记错了","有隐瞒","尚不确定"],source:"AI",evidenceIDs:[values[0].id,values[1].id],kind:"contradiction")
  XCTAssertTrue(PlotQuality.check(q,context:context,history:[]))
  XCTAssertFalse(PlotQuality.check(q,context:context,history:[q.text]))
  q.evidenceIDs=["future"];XCTAssertFalse(PlotQuality.check(q,context:context,history:[]))
  q.evidenceIDs=[values[0].id];q.choices=["一","一"];XCTAssertFalse(PlotQuality.check(q,context:context,history:[]))
  q.choices=["一","二"];q=PlotQuestion(text:"真正的凶手是这个人吗？",choices:q.choices,source:"AI",evidenceIDs:q.evidenceIDs)
  XCTAssertFalse(PlotQuality.check(q,context:context,history:[]))
 }
 func testLowConfidenceNeverUpgradesAndGoodLocalQuestionWins() {
  let policy=PlotRoutingPolicy()
  var score=PlotComplexity(complexityScore:95,confidence:0.4,reasons:["线索不明确"],relevantClues:["a"],contextSufficient:true,recommendedModel:"chatgpt")
  XCTAssertFalse(policy.wantsCloud(score,localQuality:false))
  score.confidence=0.9;XCTAssertTrue(policy.wantsCloud(score,localQuality:false));XCTAssertFalse(policy.wantsCloud(score,localQuality:true))
  score.contextSufficient=false;XCTAssertFalse(policy.wantsCloud(score,localQuality:false))
  score.contextSufficient=true;score.complexityScore=30;XCTAssertFalse(policy.wantsCloud(score,localQuality:false))
 }
 func testComplexityOutputCannotInventCluesOrOverrideInsufficientContext() {
  let a=evidence(1,"已经看到的台词")
  let context=PlotContext(cutoff:10,recent:[a],earlier:[],predictions:[])
  let text="{\"complexityScore\":80,\"confidence\":0.9,\"reasons\":[\"时间线\"],\"relevantClues\":[\"\(a.id)\"],\"contextSufficient\":true,\"recommendedModel\":\"chatgpt\"}"
  XCTAssertEqual(PlotComplexity.parse(text,context:context)?.contextSufficient,false)
  XCTAssertNil(PlotComplexity.parse(text.replacingOccurrences(of:a.id,with:"future-id"),context:context))
  XCTAssertNil(PlotComplexity.parse(text.replacingOccurrences(of:"80",with:"180"),context:context))
 }
 func testLongContextRemainsBoundedAndPreservesStructuredProvenance() {
  let values=(0..<100).map{evidence(Double($0*3),String(repeating:"台词",count:200))}
  let context=PlotContext(cutoff:400,recent:values,earlier:[],predictions:[])
  XCTAssertLessThanOrEqual(context.boundedInput.count,9500)
  XCTAssertNotNil(try? JSONDecoder().decode(PlotContext.self,from:Data(context.boundedInput.utf8)))
 }
}
@MainActor final class PlotControllerTests:XCTestCase {
 func testUnverifiedChatGPTModeFallsBackWithoutSpendingRequests() async throws {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  controller.mode = .chatgpt;controller.automaticAllowed=true;controller.consent=true;controller.creditsDisabled=true
  let cues=(0..<3).map{PlotEvidence.cue(start:Double($0*3),end:Double($0*3+2),text:"已经发生的对话\($0)",source:"test")}
  controller.frame={PlotFrame(key:"guard-test",position:10,evidence:cues)}
  controller.generate()
  for _ in 0..<30 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertEqual(controller.result?.source,"免费备用题库");XCTAssertEqual(controller.requests,0)
  XCTAssertTrue(controller.reason.contains("条件未满足"))
 }
 func testDefaultsDisableCloudAndLimitIsUserConfigurable() {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertFalse(controller.automaticAllowed);XCTAssertFalse(controller.consent);XCTAssertFalse(controller.creditsDisabled)
  XCTAssertEqual(controller.limit,10);controller.limit=30;XCTAssertEqual(controller.limit,30)
  controller.limit=100;XCTAssertEqual(controller.limit,50)
 }
 func testNoSubtitleFallbackCompletesWithoutAuthorizingCloudAndCanCancel() async throws {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  controller.mode = .fallback
  controller.frame={PlotFrame(key:"test",position:50,evidence:[])}
  controller.generate()
  for _ in 0..<30 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertEqual(controller.result?.source,"免费备用题库");XCTAssertEqual(controller.requests,0)
  controller.cancel();XCTAssertFalse(controller.working)
 }
}
