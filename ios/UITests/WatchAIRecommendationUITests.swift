import XCTest
@MainActor final class WatchAIRecommendationUITests:XCTestCase {
 private func reveal(_ element:XCUIElement,in app:XCUIApplication)->Bool {
  let list=app.descendants(matching:.any).matching(identifier:"watch-memory-list").firstMatch
  guard list.waitForExistence(timeout:10) else {return false}
  for _ in 0..<14 {
   if element.exists && element.isHittable {return true}
   let from=list.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.65))
   let to=list.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.42))
   from.press(forDuration:0.05,thenDragTo:to)
  }
  return element.exists && element.isHittable
 }
 private func openMemory(_ app:XCUIApplication) {
  let room=app.buttons["打开房间与片源"];XCTAssertTrue(room.waitForExistence(timeout:20));room.tap()
  let open=app.buttons["watch-memory-open"];XCTAssertTrue(open.waitForExistence(timeout:10));open.tap()
 }
 func testGenerateAndReopenSavedCardsUsingOfflineFixture() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_WATCH_AI_TEST"]="1";app.launch()
  openMemory(app)
  let enabled=app.switches["watch-ai-enabled"]
  guard reveal(enabled,in:app) else {XCTFail(app.debugDescription);return}
  if enabled.value as? String != "1" {enabled.tap()}
  let generate=app.buttons["watch-ai-generate"]
  guard reveal(generate,in:app) else {XCTFail(app.debugDescription);return}
  generate.tap()
  let card=app.staticTexts["ChatGPT 推荐"].firstMatch
  guard reveal(card,in:app) else {XCTFail(app.debugDescription);return}
  let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="chatgpt-recommendation-cards";attachment.lifetime = .keepAlways;add(attachment)
  app.terminate();app.launch();openMemory(app)
  XCTAssertTrue(reveal(card,in:app),app.debugDescription)
 }
}
