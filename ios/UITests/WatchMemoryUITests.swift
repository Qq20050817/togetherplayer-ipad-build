import XCTest
@MainActor final class WatchMemoryUITests:XCTestCase {
 func openSettings(_ app:XCUIApplication){let b=app.buttons["打开房间与片源"];XCTAssertTrue(b.waitForExistence(timeout:20));b.tap()}
 func testOpenMemoryAddFilmAndReopen() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  openSettings(app)
  let open=app.buttons["watch-memory-open"];XCTAssertTrue(open.waitForExistence(timeout:10));open.tap()
  let field=app.textFields["补记以前看过的电影（可带年份）"];XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("The Guilty");app.buttons["记录"].tap()
  XCTAssertTrue(app.staticTexts["为你推荐"].waitForExistence(timeout:10))
  let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="watch-memory-recommendation-cards";attachment.lifetime = .keepAlways;add(attachment)
  app.buttons["完成"].firstMatch.tap()
  app.terminate();app.launch();openSettings(app);app.buttons["watch-memory-open"].tap()
  XCTAssertFalse(app.staticTexts["看完或补记一部电影后开始推荐，评分能帮助区分喜欢和不喜欢。"].exists)
 }
}
