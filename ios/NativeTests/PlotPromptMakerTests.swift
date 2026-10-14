import XCTest
@testable import TogetherPoC

@MainActor final class PlotPromptMakerTests:XCTestCase {
 func testOnlyWellFormedQuestionsAreAccepted() {
  let valid=PlotPromptMaker.parse(#"{"question":"你认为这个人为什么隐瞒真相？","options":["保护别人","隐瞒自己","暂不确定"]}"#)
  XCTAssertEqual(valid?.choices.count,3)
  XCTAssertEqual(valid?.source,"Apple 设备端 AI")
  XCTAssertNil(PlotPromptMaker.parse(#"{"question":"猜","options":["单选"]}"#))
  XCTAssertNil(PlotPromptMaker.parse("系统无法识别剧情"))
  XCTAssertNil(PlotPromptMaker.parse(#"{"question":"这个人为什么隐瞒真相？","options":["同一个答案","同一个答案"]}"#))
 }
 func testPredictionQuestionCarriesSpecificAlternatives() {
  let parsed=PlotPromptMaker.parse(#"{"question":"发现实验室门禁卡后，接下来同伴会做什么？","options":["先尝试刷卡开门","带卡返回安全区域","把卡交给其他人"],"evidenceIDs":["source-1"],"kind":"prediction"}"#)
  XCTAssertEqual(parsed?.kind,"prediction")
  XCTAssertEqual(parsed?.choices.count,3)
  XCTAssertTrue(PlotLocalAI.questionInstructions.contains("未来剧情"))
 }
 func testFallbackCanRunWithoutSubtitlesOrAPI() async {
  let question=await PlotPromptMaker.create(excerpt:"")
  XCTAssertEqual(question.source,"免费本地题库")
  XCTAssertTrue(question.text.contains("接下来"))
  XCTAssertEqual(question.choices.count,4)
 }
}
