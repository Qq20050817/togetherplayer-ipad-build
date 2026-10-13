import XCTest
import AVFoundation
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
  q=PlotQuestion(text:q.text,choices:["一","一"],source:"AI",evidenceIDs:[values[0].id]);XCTAssertFalse(PlotQuality.check(q,context:context,history:[]))
  q=PlotQuestion(text:"真正的凶手是这个人吗？",choices:["一","二"],source:"AI",evidenceIDs:q.evidenceIDs)
  XCTAssertFalse(PlotQuality.check(q,context:context,history:[]))
 }
 func testSmartRoutingUsesRealCloudIfLocalFailsAndForComplexClues() {
  let policy=PlotRoutingPolicy()
  var score=PlotComplexity(complexityScore:95,confidence:0.4,reasons:["线索不明确"],relevantClues:["a"],contextSufficient:true,recommendedModel:"chatgpt")
  // Local assessment failure must never lock Smart mode into template-only use.
  XCTAssertTrue(policy.wantsCloud(score,localQuality:false))
  XCTAssertFalse(policy.wantsCloud(score,localQuality:true))
  score.confidence=0.9
  XCTAssertTrue(policy.wantsCloud(score,localQuality:false))
  XCTAssertTrue(policy.wantsCloud(score,localQuality:true),"high-confidence complex scenes can use ChatGPT")
  score.contextSufficient=false
  XCTAssertTrue(policy.wantsCloud(score,localQuality:false))
  score.contextSufficient=true;score.complexityScore=30
  XCTAssertTrue(policy.wantsCloud(score,localQuality:false))
  XCTAssertFalse(policy.wantsCloud(score,localQuality:true),"a good local question saves cloud usage")
  XCTAssertTrue(policy.wantsCloud(score,localQuality:false,contextSufficient:false),"manual smart request can ask a general question")
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
  XCTAssertLessThanOrEqual(context.localInput.count,3000)
  XCTAssertNotNil(try? JSONDecoder().decode(PlotContext.self,from:Data(context.boundedInput.utf8)))
 }
}
@MainActor final class PlotControllerTests:XCTestCase {
 func testSameFilmReconnectRetainsSavedSubtitlesAndNewFilmStaysIsolated() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let film=PlotMemoryStore.key("room-film-A"),other=PlotMemoryStore.key("room-film-B")
  var cues:[PlotEvidence]=[]
  for i in 0..<8 {
   let start=Double(i)*4
   let text="已播放的第"+String(i)+"句字幕"
   cues.append(PlotEvidence.cue(start:start,end:start+2,text:text,source:"embedded-subtitle"))
  }
  _ = try await PlotMemoryStore(directory:root).ingest(cues,cutoff:50,key:film)
  // A fresh store/controller simulates the reopened transport and player.
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:root),preferences:UserDefaults(suiteName:UUID().uuidString)!)
  controller.frame={PlotFrame(key:film,position:50,evidence:[])}
  await controller.collect()
  XCTAssertEqual(controller.collectedSubtitleCount,cues.count)
  controller.frame={PlotFrame(key:film,position:18,evidence:[])}
  await controller.collect()
  XCTAssertEqual(controller.collectedSubtitleCount,cues.count,"rewind retains local memory while contexts still obey the cutoff")
  let stored=await PlotMemoryStore(directory:root).load(film)
  let context=stored.context(at:18)
  XCTAssertTrue(context.recent.allSatisfy{$0.end<=18})
  controller.frame={PlotFrame(key:other,position:50,evidence:[])}
  XCTAssertEqual(controller.collectedSubtitleCount,0,"never show another film's evidence before loading")
  await controller.collect()
  XCTAssertEqual(controller.collectedSubtitleCount,0)
 }
 func testSubtitleDocumentSurvivesReconnectButClearsForNewFilm() async throws {
  let player=AVPlayer()
  let subtitles=ExternalSubtitles(player:player,preferences:UserDefaults(suiteName:UUID().uuidString)!)
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".srt")
  defer {try? FileManager.default.removeItem(at:temp)}
  try Data("1\n00:00:01,000 --> 00:00:03,000\n已经观看的字幕\n".utf8).write(to:temp)
  subtitles.beginPlotFilm("film-A")
  let imported=await subtitles.importFile(temp)
  XCTAssertTrue(imported)
  XCTAssertTrue(subtitles.available)
  subtitles.beginPlotFilm("film-A")
  XCTAssertTrue(subtitles.available,"same-film reconnect must not discard imported subtitles")
  subtitles.beginPlotFilm("film-B")
  XCTAssertFalse(subtitles.available,"a genuinely different film must not inherit subtitles")
 }
 func testAutoPromptExplainsUnavailableRoomAndFreeModel() {
  let model=TestClient(automaticallyConnect:false)
  model.plotIntelligence.eventDrivenEnabled=true
  model.plotIntelligence.mode = .smart
  model.plotIntelligence.subtitleChanged("")
  XCTAssertTrue(model.plotIntelligence.autoTriggerStatus.contains("房间"),"no room must not silently skip")
  model.plotIntelligence.mode = .fallback
  model.plotIntelligence.subtitleChanged("")
  XCTAssertTrue(model.plotIntelligence.autoTriggerStatus.contains("手动"),"free questions require explicit manual request")
 }
 func testUnansweredBlockingPollRejectsPlaybackLocally() {
  let model=TestClient(automaticallyConnect:false)
  model.plotPoll=["waitingForAnswers":true]
  model.control("PLAY")
  XCTAssertTrue(model.requestStatus.contains("先回答"))
  XCTAssertFalse(model.supportsBlockingPolls,"older servers must not falsely advertise this mode")
 }
 func testExplicitChatGPTNeverSilentlyUsesFallbackOrSpendsWithoutConsent() async throws {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let store=PlotMemoryStore(directory:nil)
  let controller=PlotIntelligence(memory:store,preferences:preferences)
  controller.mode = .chatgpt;controller.automaticAllowed=false;controller.consent=false;controller.creditsDisabled=false
  var cues:[PlotEvidence]=[]
  for i in 0..<3 {
   let start=Double(i)*3
   let phrase="已经发生的对话"+String(i)
   cues.append(PlotEvidence.cue(start:start,end:start+2,text:phrase,source:"test"))
  }
  let frame=PlotFrame(key:"guard-test",position:10,evidence:cues)
  controller.frame={frame}
  // A previously cached free-template question must not masquerade as ChatGPT.
  let context=PlotContext(cutoff:10,recent:cues,earlier:[],predictions:[])
  let fallback=PlotFallback.question(context:context,history:[])
  try await store.finish(key:frame.key,question:fallback,cutoff:10,clues:[],context:context)
  controller.generate()
  for _ in 0..<80 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertNil(controller.result)
  XCTAssertEqual(controller.selectedModel,"ChatGPT 未出题")
  XCTAssertTrue(controller.reason.contains("同意"))
  XCTAssertEqual(controller.requests,0)
 }
 func testManualChatGPTWithoutSubtitlesExplainsConsentInsteadOfReturningTemplate() async throws {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  controller.mode = .chatgpt
  controller.frame={PlotFrame(key:"no-subtitles",position:80,evidence:[])}
  controller.generate()
  for _ in 0..<80 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertNil(controller.result)
  XCTAssertEqual(controller.selectedModel,"ChatGPT 未出题")
  XCTAssertTrue(controller.reason.contains("同意"))
  XCTAssertEqual(controller.requests,0)
 }
 func testExplicitLocalModeDoesNotClaimFreeTemplateWasRealAI() async throws {
  guard !PlotLocalAI.available else {return} // Device-specific model availability.
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  controller.mode = .local
  controller.frame={PlotFrame(key:"no-device-model",position:80,evidence:[])}
  controller.generate()
  for _ in 0..<80 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertNil(controller.result)
  XCTAssertEqual(controller.selectedModel,"苹果本地 AI 未出题")
  XCTAssertTrue(controller.reason.contains("暂不可用"))
 }
 func testSmartModeNeverMasqueradesAsFreeTemplateWithoutAvailableModels() async throws {
  guard !PlotLocalAI.available else {return}
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let store=PlotMemoryStore(directory:nil)
  let controller=PlotIntelligence(memory:store,preferences:preferences)
  controller.mode = .fallback
  controller.frame={PlotFrame(key:"smart-no-model",position:80,evidence:[])}
  controller.generate()
  for _ in 0..<80 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertEqual(controller.result?.source,"免费备用题库")
  controller.mode = .smart
  XCTAssertNil(controller.result,"switching models must clear stale free preview")
  controller.generate()
  for _ in 0..<80 {if !controller.working {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertNil(controller.result)
  XCTAssertEqual(controller.selectedModel,"智能模式未出题")
  XCTAssertTrue(controller.reason.contains("ChatGPT") || controller.reason.contains("设备端模型"))
  XCTAssertEqual(controller.requests,0)
 }
 func testQuestionPauseSettingPersistsAcrossControllerRecreationAndCancellation() {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let initial=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertTrue(initial.pauseForQuestions,"answer-before-resume is the default requested behavior")
  initial.pauseForQuestions=false
  initial.cancel()
  let reopened=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertFalse(reopened.pauseForQuestions)
  reopened.pauseForQuestions=true
  reopened.cancel()
  let relaunched=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertTrue(relaunched.pauseForQuestions)
 }
  func testDefaultsDisableCloudAndLimitIsUserConfigurable() {
  let preferences=UserDefaults(suiteName:UUID().uuidString)!
  let controller=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertFalse(controller.automaticAllowed);XCTAssertFalse(controller.consent);XCTAssertFalse(controller.creditsDisabled)
  XCTAssertEqual(controller.limit,10);controller.limit=30;XCTAssertEqual(controller.limit,30)
  controller.limit=100;XCTAssertEqual(controller.limit,50)
  XCTAssertEqual(preferences.integer(forKey:"plot-cloud-limit"),50)
  controller.limit = -5;XCTAssertEqual(controller.limit,1)
  controller.limit=1;XCTAssertEqual(controller.limit,1)
  XCTAssertEqual(preferences.integer(forKey:"plot-cloud-limit"),1)
  controller.limit=30
  let reopened=PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:preferences)
  XCTAssertEqual(reopened.limit,30)
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


final class PlotVisualFrameClockTests:XCTestCase {
 func testSamplesCurrentFrameAndNeverLooksAhead() throws {
  let near=try XCTUnwrap(PlotVisualFrameClock.itemTime(host:CMTime(seconds:30.02,preferredTimescale:600),playhead:30))
  XCTAssertEqual(near.seconds,30,accuracy:0.002)
  let behind=try XCTUnwrap(PlotVisualFrameClock.itemTime(host:CMTime(seconds:29.99,preferredTimescale:600),playhead:30))
  XCTAssertEqual(behind.seconds,29.99,accuracy:0.002)
  XCTAssertGreaterThan(behind.seconds,29.75,"Video output must not query an old quarter-second offset")
 }
 func testInvalidHostClockFallsBackSafelyToKnownPlayhead() throws {
  let time=try XCTUnwrap(PlotVisualFrameClock.itemTime(host:.invalid,playhead:22))
  XCTAssertEqual(time.seconds,22,accuracy:0.002)
  XCTAssertNil(PlotVisualFrameClock.itemTime(host:.invalid,playhead:.nan))
  XCTAssertNil(PlotVisualFrameClock.itemTime(host:.invalid,playhead:-1))
 }
}
