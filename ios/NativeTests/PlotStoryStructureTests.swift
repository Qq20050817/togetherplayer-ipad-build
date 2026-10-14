import XCTest
@testable import TogetherPoC

final class PlotStoryStructureTests:XCTestCase {
 private func transcript()->SubtitleDocument {
  SubtitleDocument((0..<60).map {i in
   let time=Double(i)*180+45
   let script=i<30 ? "警方在这场调查中发现重要线索，证词有新的矛盾 \(i)" :
     "随后另一段调查揭示有新的嫌疑人与动机 \(i)"
   return SubtitleCue(start:time,end:time+3,text:script)
  })
 }
 func testCompleteMovieIsPartitionedIntoBoundedChronologicalStoryWindows() {
  let document=transcript()
  let parts=PlotStoryStructure.windows(document)
  XCTAssertGreaterThanOrEqual(parts.count,8)
  XCTAssertLessThanOrEqual(parts.count,18)
  XCTAssertEqual(parts.map(\.start),parts.map(\.start).sorted(),
   "Movie story sections must follow chronological order")
  XCTAssertTrue(parts.allSatisfy{part in part.cues.allSatisfy{cue in cue.end<=part.end && cue.end>cue.start}})
  let beginning=try? XCTUnwrap(parts.first)
  if let beginning {
   let evidence=PlotStoryStructure.context(beginning,source:"embedded-subtitle")
   XCTAssertFalse(evidence.recent.isEmpty)
   XCTAssertFalse(evidence.input.contains("新的嫌疑人"),
    "The beginning of the movie must not access later plot developments")
  }
 }
 func testModelJsonRequiresExactReferencedEvidenceAndNeverTakesUnwatchedFacts() throws {
  let document=transcript(),part=try XCTUnwrap(PlotStoryStructure.windows(document).first)
  let context=PlotStoryStructure.context(part,source:"embedded-subtitle")
  let valid=try XCTUnwrap(context.recent.first)
  let good:[String:Any]=[
   "summary":"警方调查发现了新的证词矛盾，仍需查证",
   "characters":["调查人员"],"events":["调查取得线索"],
   "motivations":["可能有人隐瞒"],"relationships":["当事人和调查者"],
   "unresolved":["证词为什么相互矛盾"],"causalLinks":["先前证词引发调查"],
   "evidenceIDs":[valid.id],"confidence":0.7
  ]
  let text=String(data:try JSONSerialization.data(withJSONObject:good),encoding:.utf8)!
  let parsed=try XCTUnwrap(PlotStoryStructure.parse(text,window:part,context:context))
  XCTAssertEqual(parsed.evidenceIDs,[valid.id])
  XCTAssertNotNil(PlotStoryStructure.parse(text,window:part,context:context))
  var poisoned=good;poisoned["evidenceIDs"]=["future-uncited-id"]
  let attack=String(data:try JSONSerialization.data(withJSONObject:poisoned),encoding:.utf8)!
  XCTAssertNil(PlotStoryStructure.parse(attack,window:part,context:context))
 }
 func testChangingSubtitleTrackCannotReuseAnotherLanguageStoryGraph() {
  let english=SubtitleDocument([SubtitleCue(start:10,end:12,text:"Evidence discovered"),
    SubtitleCue(start:40,end:43,text:"Where were you last night?")])
  let chinese=SubtitleDocument([SubtitleCue(start:10,end:12,text:"找到新证据"),
    SubtitleCue(start:40,end:43,text:"你昨晚在哪里？")])
  XCTAssertNotEqual(PlotStoryStructure.transcriptFingerprint(english),
   PlotStoryStructure.transcriptFingerprint(chinese))
 }
 func testCachedFutureSceneNeverAppearsInRebuiltEarlierScenePrompt() {
  let current=PlotEvidence.cue(start:102,end:105,text:"我还在调查中",source:"embedded-subtitle")
  let context=PlotContext(cutoff:110,recent:[current],earlier:[],predictions:[])
  let historic=PlotStoryNode(start:0,end:60,summary:"早先发生一场调查",
   characters:[],events:[],motivations:[],relationships:[],unresolved:[],causalLinks:[],
   evidenceIDs:["previous"],confidence:0.6)
  let future=PlotStoryNode(start:190,end:290,summary:"未来揭晓的幕后主使身份",
   characters:[],events:[],motivations:[],relationships:[],unresolved:[],causalLinks:[],
   evidenceIDs:["future"],confidence:0.6)
  let prompt=PlotStoryStructure.prompt(context,previous:[historic,future])
  XCTAssertTrue(prompt.contains("早先发生一场调查"))
  XCTAssertFalse(prompt.contains("未来揭晓"))
 }
  func testJumpToLaterSceneCannotRevealUnwatchedTenMinuteSummary() {
  let early=PlotEvidence.cue(start:15,end:18,text:"最初发现的蓝色钥匙",source:"embedded-subtitle")
  let middle=PlotEvidence.cue(start:300,end:303,text:"调查蓝色钥匙的来源",source:"embedded-subtitle")
  let late=PlotEvidence.cue(start:590,end:593,text:"蓝色钥匙被交给警方",source:"embedded-subtitle")
  let whole=PlotStoryNode(start:0,end:600,summary:"蓝色钥匙关系到全部事件",
   characters:[],events:[],motivations:[],relationships:[],unresolved:[],
   causalLinks:[],evidenceIDs:[early.id],confidence:0.6)
  XCTAssertTrue(PlotStoryStructure.observedClues([whole],watched:[early],at:601).isEmpty,
   "Watching just one dialogue before seeking to the end must not reveal the full scene recap")
  let connected=PlotStoryStructure.observedClues([whole],watched:[early,middle,late],at:601)
  XCTAssertEqual(connected.count,1)
 }
  func testNoFutureNodeCanEnterCurrentWatchedMemory() {
  let early=PlotEvidence.cue(start:10,end:13,text:"有人报告秘密实验",source:"embedded-subtitle")
  let later=PlotEvidence.cue(start:100,end:103,text:"随后发现实验真相",source:"embedded-subtitle")
  func node(_ time:Double,_ cue:PlotEvidence)->PlotStoryNode {
   PlotStoryNode(start:time-10,end:time,summary:cue.text,characters:[],
    events:[cue.text],motivations:[],relationships:[],unresolved:[],causalLinks:[],
    evidenceIDs:[cue.id],confidence:0.65)
  }
  let nodes=[node(18,early),node(110,later)]
  let before=PlotStoryStructure.observedClues(nodes,watched:[early],at:60)
  XCTAssertEqual(before.count,1)
  XCTAssertTrue(before[0].text.contains("秘密实验"))
  XCTAssertFalse(before[0].text.contains("真相"))
  let missed=PlotStoryStructure.observedClues(nodes,watched:[],at:300)
  XCTAssertTrue(missed.isEmpty,"Skipped scene data cannot masquerade as watched plot evidence")
 }
 @MainActor func testLocalStoryArchiveRestoresSameFilmWithoutSharingOtherMovie() async throws {
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:dir)}
  let archive=PlotStoryArchive(directory:dir)
  let node=PlotStoryNode(start:0,end:90,summary:"相关人物刚开始讨论调查",
   characters:["警方"],events:["调查"],motivations:[],relationships:[],
   unresolved:[],causalLinks:[],evidenceIDs:["a"],confidence:0.6)
  try await archive.write([node],key:"film-A")
  let restored=await archive.read(key:"film-A")
  let other=await archive.read(key:"film-B")
  XCTAssertEqual(restored,[node])
  XCTAssertEqual(other,[])
 }
}
