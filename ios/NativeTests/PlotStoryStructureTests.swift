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
  XCTAssertEqual(parts,parts.sorted{$0.start<$1.start},
   "Movie story sections must follow chronological order")
  XCTAssertTrue(parts.allSatisfy{$0.cues.allSatisfy{$0.end<=$0.end && $0.end>$0.start}})
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
  XCTAssertEqual(await archive.read(key:"film-A"),[node])
  XCTAssertEqual(await archive.read(key:"film-B"),[])
 }
}
