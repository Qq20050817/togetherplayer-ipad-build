import XCTest
@testable import TogetherPoC

final class SubtitleVerificationPlanTests: XCTestCase {
 func testThreeDialogueSamplesPerThird() {
  let captions = (0..<90).map { n in
   SubtitleCue(start:Double(n)*12+2,end:Double(n)*12+5,text:"第\(n)句对白")
  }
  let samples = SubtitleVerificationPlan.samples(document:SubtitleDocument(captions),duration:1080)
  XCTAssertEqual(samples.count,9)
  XCTAssertEqual(samples.map(\.index),Array(1...9))
  for third in 0..<3 {
   XCTAssertEqual(samples[(third*3)..<(third*3+3)].count,3)
   XCTAssertTrue(samples[(third*3)..<(third*3+3)].allSatisfy {
    $0.subtitleStartSeconds >= Double(third)*360 && $0.subtitleStartSeconds < Double(third+1)*360
   })
  }
  XCTAssertTrue(samples.allSatisfy{$0.durationSeconds==10 && $0.startSeconds>=0 && $0.startSeconds+10<=1080})
 }
 func testNoInventedDialogueSamples() {
  let doc=SubtitleDocument([SubtitleCue(start:10,end:14,text:"你好")])
  XCTAssertTrue(SubtitleVerificationPlan.samples(document:doc,duration:600).isEmpty)
 }
 func testRejectsInvalidDuration() {
  XCTAssertTrue(SubtitleVerificationPlan.samples(document:SubtitleDocument([]),duration:.infinity).isEmpty)
 }
}
