import XCTest
@testable import TogetherPoC

@MainActor final class PlotPanelReadTests:XCTestCase {
 func testPanelReadsDoNotBuildEvidenceAndStillInvalidateOnFilmChange() async {
  let defaults=UserDefaults(suiteName:UUID().uuidString)!
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let intelligence=PlotIntelligence(memory:PlotMemoryStore(directory:root),preferences:defaults)
  var expensiveReads=0
  var key="film-a"
  intelligence.frame={expensiveReads+=1;return PlotFrame(key:key,position:50,evidence:[])}
  intelligence.displayPosition={PlotDisplayPosition(key:key,position:50)}
  await intelligence.collect()
  expensiveReads=0
  for _ in 0..<200 {
   XCTAssertTrue(intelligence.previewUsable)
   XCTAssertEqual(intelligence.collectedSubtitleCount,0)
  }
  XCTAssertEqual(expensiveReads,0,"rendering must not scan/hash a film's subtitle evidence or checkpoints")
  key="film-b"
  XCTAssertFalse(intelligence.previewUsable)
  XCTAssertEqual(intelligence.collectedSubtitleCount,0)
  XCTAssertEqual(expensiveReads,0)
 }
 func testUnloadedPresentationNeverFallsBackToBuildingEvidence() {
  let intelligence=PlotIntelligence(preferences:UserDefaults(suiteName:UUID().uuidString)!)
  var expensiveReads=0
  intelligence.frame={expensiveReads+=1;return PlotFrame(key:"old-film",position:50,evidence:[])}
  intelligence.displayPosition={nil}
  XCTAssertFalse(intelligence.previewUsable)
  XCTAssertEqual(intelligence.collectedSubtitleCount,0)
  XCTAssertEqual(expensiveReads,0)
 }
}
