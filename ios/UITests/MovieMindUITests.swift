import XCTest

final class MovieMindUITests: XCTestCase {
  func testIndependentEntryAndSwitchesReturnToExistingRoomUI() {
    let app = XCUIApplication()
    app.launchEnvironment["TOGETHER_UI_TEST"] = "1"
    app.launch()
    XCUIDevice.shared.orientation = .landscapeLeft
    let settings = app.buttons["打开房间与片源"]
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    settings.tap()
    let entry = app.buttons["moviemind-open"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10))
    entry.tap()
    XCTAssertTrue(app.navigationBars["MovieMind"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.switches["启用 MovieMind"].exists)
    XCTAssertTrue(app.switches["实际播放区间记录"].exists)
    XCTAssertTrue(app.switches["可跳过的片尾评分卡"].exists)
    app.navigationBars["MovieMind"].buttons["完成"].tap()
    XCTAssertTrue(entry.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["创建房间"].exists)
  }
}
