import XCTest
@MainActor final class WatchAIRecommendationUITests:XCTestCase {
 func testGenerateAndReopenSavedCardsUsingOfflineFixture() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_WATCH_AI_TEST"]="1";app.launch()
  let room=app.buttons["打开房间与片源"];XCTAssertTrue(room.waitForExistence(timeout:20));room.tap()
  app.buttons["watch-memory-open"].tap()
  let generate=app.buttons["watch-ai-generate"]
  for _ in 0..<4 {if generate.isHittable {break};app.swipeUp()}
  XCTAssertTrue(generate.waitForExistence(timeout:10));generate.tap()
  let card=app.otherElements["watch-ai-card"]
  for _ in 0..<5 {if app.staticTexts["ChatGPT 推荐"].firstMatch.isHittable {break};app.swipeUp()}
  XCTAssertTrue(app.staticTexts["ChatGPT 推荐"].firstMatch.waitForExistence(timeout:10))
  let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="chatgpt-recommendation-cards";attachment.lifetime = .keepAlways;add(attachment)
  _=card
  app.terminate();app.launch()
  XCTAssertTrue(room.waitForExistence(timeout:20));room.tap();app.buttons["watch-memory-open"].tap()
  for _ in 0..<6 {if app.staticTexts["ChatGPT 推荐"].firstMatch.isHittable {break};app.swipeUp()}
  XCTAssertTrue(app.staticTexts["ChatGPT 推荐"].firstMatch.exists)
 }
}
