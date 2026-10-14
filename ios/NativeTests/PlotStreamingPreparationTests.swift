import XCTest
@testable import TogetherPoC

@MainActor final class PlotStreamingPreparationTests:XCTestCase {
 private func evidence()->[PlotEvidence] {
  (0..<6).map {i in PlotEvidence.cue(start:Double(i)*20+5,end:Double(i)*20+8,text:"警方正在调查蓝色钥匙的来源，证词还有矛盾 \(i)",source:"embedded-subtitle")}
 }
 private func controller()->PlotIntelligence {
  PlotIntelligence(memory:PlotMemoryStore(directory:nil),preferences:UserDefaults(suiteName:UUID().uuidString)!)
 }
 private func question(_ cues:[PlotEvidence])->PlotQuestion {
  PlotQuestion(text:"警方找到的蓝色钥匙为什么与证词矛盾？",choices:["证人隐瞒来源","有人交换钥匙","还需核实时间"],source:"Apple 设备端 AI",evidenceIDs:[cues.last!.id],kind:"contradiction")
 }
 func testStreamingEvidenceStartsRealPreparationWithoutFullIndexAndNeverSendsFuture() async throws {
  let model=controller(),past=evidence()
  let future=PlotEvidence.cue(start:400,end:403,text:"未来结局绝不能进入输入",source:"embedded-subtitle")
  let key="streaming-"+UUID().uuidString
  model.frame={PlotFrame(key:key,position:130,evidence:past+[future])}
  model.storyModelAvailable={true}
  var inputs:[String]=[]
  model.storyInference={_,input in
   inputs.append(input)
   let object:[String:Any]=["summary":"警方正在调查钥匙来源，证词仍有疑点","evidenceIDs":[past[0].id],"confidence":0.7]
   return String(data:try JSONSerialization.data(withJSONObject:object),encoding:.utf8)!
  }
  await model.collect()
  for _ in 0..<100 {if model.fullFilmPreparationStatus.contains("已整理"){break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertEqual(inputs.count,1,"live watched cues must reach the model without an entire-movie HLS scan")
  XCTAssertFalse(try XCTUnwrap(inputs.first).contains("未来结局"))
  XCTAssertTrue(model.fullFilmPreparationStatus.contains("已整理1段"))
  await model.collect()
  XCTAssertEqual(inputs.count,1,"ordinary 20-second collection must not repeat background inference")
 }
 func testFullDocumentCannotBypassWatchedEvidenceGate() async throws {
  let model=controller(),past=evidence()
  model.frame={PlotFrame(key:"watched-only-"+past[0].id,position:130,evidence:past)}
  model.storyModelAvailable={true}
  var inputs:[String]=[]
  model.storyInference={_,input in inputs.append(input);return "{}"}
  let doc=SubtitleDocument(past.map{SubtitleCue(start:$0.start,end:$0.end,text:$0.text)}+[SubtitleCue(start:200,end:205,text:"尚未观看的反转结局")])
  model.prepareFullFilm(doc,source:"embedded-subtitle",key:"watched-only-"+past[0].id,checkpoints:[])
  for _ in 0..<100 {if !inputs.isEmpty {break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertEqual(inputs.count,1)
  XCTAssertFalse(try XCTUnwrap(inputs.first).contains("尚未观看的反转"))
 }
 func testAutomaticQuestionSurvivesDialogueAndPublishesExactlyOnceAtNextGap() {
  let model=controller(),cues=evidence()
  let frame=PlotFrame(key:"film",position:130,evidence:cues)
  model.frame={frame};model.eventDrivenEnabled=true
  var speaking=true,published:[PlotQuestion]=[]
  model.isSubtitleCurrentlyShown={speaking};model.mayPublishAutomatically={true}
  model.publishAutomatically={published.append($0)}
  model.queueAutomaticQuestion(question(cues),snapshot:frame,token:0)
  XCTAssertTrue(published.isEmpty)
  XCTAssertTrue(model.autoTriggerStatus.contains("等待"))
  speaking=false
  model.subtitleChanged("")
  XCTAssertEqual(published.count,1)
  XCTAssertTrue(published.first?.blocking == true)
  XCTAssertFalse(model.publishPendingAutomaticQuestion())
  XCTAssertEqual(published.count,1)
  model.playbackJumped()
 }
 func testClosingSettingsOnlyCancelsInteractiveAnalysisNotAutomaticGeneration() {
  let model=controller(),cues=evidence()
  model.frame={PlotFrame(key:"film",position:130,evidence:cues)}
  model.generate(autoMoment:true)
  XCTAssertTrue(model.working)
  XCTAssertFalse(model.shouldCancelOnPanelDismissal)
  model.cancel()
  model.generate()
  XCTAssertTrue(model.shouldCancelOnPanelDismissal)
  model.cancel()
 }
 func testMissingCueEndCallbackCannotHoldAReadyQuestionForever() {
  let model=controller(),cues=evidence()
  let frame=PlotFrame(key:"film",position:130,evidence:cues)
  var now=Date(timeIntervalSince1970:100),published=0
  model.frame={frame};model.eventDrivenEnabled=true
  model.automaticQuestionNow={now}
  model.isSubtitleCurrentlyShown={true};model.mayPublishAutomatically={true}
  model.publishAutomatically={_ in published+=1}
  model.queueAutomaticQuestion(question(cues),snapshot:frame,token:0)
  XCTAssertEqual(published,0)
  now=now.addingTimeInterval(9)
  XCTAssertTrue(model.publishPendingAutomaticQuestion())
  XCTAssertEqual(published,1)
  XCTAssertFalse(model.publishPendingAutomaticQuestion())
 }
 func testQueuedQuestionCannotLeakAfterFilmChangeOrRewind() {
  for rewind in [false,true] {
   let model=controller(),cues=evidence()
   let initial=PlotFrame(key:"film",position:130,evidence:cues)
   var current=initial,speaking=true,published=0
   model.frame={current};model.eventDrivenEnabled=true
   model.isSubtitleCurrentlyShown={speaking};model.mayPublishAutomatically={true}
   model.publishAutomatically={_ in published+=1}
   model.queueAutomaticQuestion(question(cues),snapshot:initial,token:0)
   current=PlotFrame(key:rewind ? "film" : "other",position:rewind ? 100 : 135,evidence:cues)
   speaking=false
   XCTAssertFalse(model.publishPendingAutomaticQuestion())
   XCTAssertEqual(published,0)
  }
 }
 func testQueuedQuestionRevalidatesCurrentEvidenceBeforePausing() {
  let model=controller(),cues=evidence()
  let initial=PlotFrame(key:"film",position:130,evidence:cues)
  var current=initial,speaking=true,published=0
  model.frame={current};model.eventDrivenEnabled=true
  model.isSubtitleCurrentlyShown={speaking};model.mayPublishAutomatically={true}
  model.publishAutomatically={_ in published+=1}
  model.queueAutomaticQuestion(question(cues),snapshot:initial,token:0)
  let newer=(0..<8).map{PlotEvidence.cue(start:130+Double($0)*2,end:131+Double($0)*2,text:"人物已经讨论另一个新事件 \($0)",source:"embedded-subtitle")}
  current=PlotFrame(key:"film",position:150,evidence:newer);speaking=false
  XCTAssertFalse(model.publishPendingAutomaticQuestion())
  XCTAssertEqual(published,0)
 }
 func testLoopbackPlannedHLSIsNotMistakenForAnExistingFullTranscript() throws {
  XCTAssertTrue(NativeSubtitleIndexReader.isDemandDrivenLocal(master:try XCTUnwrap(URL(string:"http://127.0.0.1:8123/movie/master.m3u8"))))
  XCTAssertFalse(NativeSubtitleIndexReader.isDemandDrivenLocal(master:try XCTUnwrap(URL(string:"https://media.example/master.m3u8"))))
  XCTAssertFalse(NativeSubtitleIndexReader.isDemandDrivenLocal(master:try XCTUnwrap(URL(string:"http://127.0.0.1:8123/movie.mp4"))))
 }
 func testWatchedWindowsExcludeFutureAndKeepCompletedBoundsStable() {
  let old=evidence(),future=PlotEvidence.cue(start:610,end:615,text:"后续线索",source:"embedded-subtitle")
  let before=PlotStoryStructure.watchedWindows(old+[future],at:130)
  XCTAssertEqual(before.count,1)
  XCTAssertFalse(before[0].cues.contains{$0.text==future.text})
  let grown=PlotStoryStructure.watchedWindows(old+[future],at:620)
  XCTAssertEqual(grown[0].start,0)
  XCTAssertEqual(grown[0].end,600)
  XCTAssertEqual(grown[0].cues.count,old.count)
 }
}
