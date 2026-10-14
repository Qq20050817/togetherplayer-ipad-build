import XCTest
@testable import TogetherPoC

final class PlotPredictionReviewTests:XCTestCase {
 let sample="""
 {"index":1,"confidence":0.94,"evidenceID":"future-2"}
 """
 func testReviewStartsOnlyAfterThreeMinutesAndStopsAfterEight() {
  let r=PlotPendingReview(id:"p",roomId:"r",mediaId:"movie",at:100,
   question:"在找到门禁卡之后，接下来谁最可能进入实验室？",
   choices:["门外的人离开","同伴试图打开实验室","实验室立即爆炸"],answers:["one":"同伴试图打开实验室"])
  XCTAssertTrue(r.isReady)
  XCTAssertFalse(r.canReview(position:279))
  XCTAssertTrue(r.canReview(position:280))
  XCTAssertFalse(r.canReview(position:581))
 }
 func testStrictVerdictRequiresObservedFutureSubtitleAndConfidence() {
  let observed=[PlotEvidence(id:"future-2",start:282,end:290,text:"我们进实验室吧",source:"embedded-subtitle")]
  let choices=["门外的人离开","同伴试图打开实验室","实验室立即爆炸"]
  XCTAssertEqual(PlotPredictionVerdict.parse(sample,choices:choices,observed:observed)?.index,1)
  XCTAssertNil(PlotPredictionVerdict.parse(sample,choices:choices,observed:[]))
  XCTAssertNil(PlotPredictionVerdict.parse(#"{"index":1,"confidence":0.72,"evidenceID":"future-2"}"#,choices:choices,observed:observed))
  XCTAssertNil(PlotPredictionVerdict.parse(#"{"index":4,"confidence":1,"evidenceID":"future-2"}"#,choices:choices,observed:observed))
  XCTAssertNil(PlotPredictionVerdict.parse(#"{"index":-1,"confidence":0,"evidenceID":""}"#,choices:choices,observed:observed))
 }
 func testNoFutureEvidenceLeakAndNoEarlyCorrectAnswer() {
  let r=PlotPendingReview(id:"p",roomId:"r",mediaId:"movie",at:100,
   question:"之后门后面会发生什么？",choices:["有人开门","无人回应"],answers:["one":"有人开门"])
  let watched=[PlotEvidence(id:"before",start:95,end:99,text:"这里有人吗",source:"embedded-subtitle"),
   PlotEvidence(id:"after",start:181,end:185,text:"没人应答",source:"embedded-subtitle"),
   PlotEvidence(id:"beyond",start:602,end:604,text:"他们还在等",source:"embedded-subtitle")]
  XCTAssertEqual(r.observed(watched,position:190).map(\.id),["after"])
  XCTAssertTrue(PlotPredictionQuality.isVague("无法确定"))
 }
}
