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

extension MovieMindUITests {
  func testNativeRecordReviewEditAndRecommendationsStayInsideApp() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["TOGETHER_UI_TEST"] = "1"
    app.launch()
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.buttons["打开房间与片源"].waitForExistence(timeout: 15))
    app.buttons["打开房间与片源"].tap()
    XCTAssertTrue(app.buttons["moviemind-open"].waitForExistence(timeout: 10))
    app.buttons["moviemind-open"].tap()
    let origin = app.textFields["moviemind-origin"]
    reveal(origin, in: app)
    replace(origin, with: "http://127.0.0.1:18089")
    replace(app.textFields["moviemind-username"], with: "fixture_user")
    app.secureTextFields["moviemind-password"].tap()
    app.secureTextFields["moviemind-password"].typeText("synthetic-ui-password-731")
    reveal(app.buttons["登录此服务"], in: app)
    app.buttons["登录此服务"].tap()
    let status = app.staticTexts["moviemind-sync-status"]
    let accepted = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "已登录独立", "仅本次登录成功")
    let expectation = XCTNSPredicateExpectation(predicate: accepted, object: status)
    if XCTWaiter.wait(for: [expectation], timeout: 8) != .completed {
      let temporary = app.buttons["仅本次登录"]
      XCTAssertTrue(temporary.waitForExistence(timeout: 5))
      temporary.tap()
      XCTAssertEqual(
        XCTWaiter.wait(
          for: [XCTNSPredicateExpectation(predicate: accepted, object: status)], timeout: 10),
        .completed)
    }
    let library = app.descendants(matching: .any).matching(identifier: "moviemind-native-library")
      .firstMatch
    reveal(library, in: app, upward: false)
    library.tap()
    XCTAssertTrue(app.navigationBars["我的电影与评分"].waitForExistence(timeout: 10))
    app.buttons["moviemind-add-seen"].tap()
    XCTAssertTrue(app.textFields["moviemind-entry-title"].waitForExistence(timeout: 5))
    app.textFields["moviemind-entry-title"].tap()
    app.textFields["moviemind-entry-title"].typeText("仅用于界面测试的电影")
    let existing = app.buttons["使用已有：仅用于界面测试的电影（2020）"]
    XCTAssertTrue(existing.waitForExistence(timeout: 5))
    existing.tap()
    let review = app.descendants(matching: .any).matching(identifier: "moviemind-entry-comment")
      .firstMatch
    review.tap()
    review.typeText("节奏紧张，愿意再看。仅用于界面测试。")
    reveal(app.buttons["moviemind-save-entry"], in: app)
    app.buttons["moviemind-save-entry"].tap()
    let unrated = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "仅用于界面测试的电影", "已看 · 未评分")
    ).firstMatch
    XCTAssertTrue(unrated.waitForExistence(timeout: 15))
    unrated.tap()
    let score = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "个人评分")
    ).firstMatch
    XCTAssertTrue(score.waitForExistence(timeout: 5))
    score.tap()
    XCTAssertTrue(app.buttons["8.5"].waitForExistence(timeout: 5))
    app.buttons["8.5"].tap()
    reveal(app.buttons["moviemind-save-entry"], in: app)
    app.buttons["moviemind-save-entry"].tap()
    let rated = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "仅用于界面测试的电影", "已看 · 8.5 分")
    ).firstMatch
    XCTAssertTrue(rated.waitForExistence(timeout: 15))
    app.navigationBars.buttons["MovieMind"].tap()
    let discover = app.descendants(matching: .any).matching(identifier: "moviemind-native-discover")
      .firstMatch
    reveal(discover, in: app)
    discover.tap()
    XCTAssertTrue(app.navigationBars["推荐下一部"].waitForExistence(timeout: 5))
    reveal(app.buttons["moviemind-native-recommend"], in: app)
    app.buttons["moviemind-native-recommend"].tap()
    let next = app.staticTexts["仅用于界面测试的下一部 · 2021"]
    XCTAssertTrue(next.waitForExistence(timeout: 10))
    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertNotEqual(
      XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").state, .runningForeground)
  }
  private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
    for _ in 0..<7 {
      if element.exists && element.isHittable { return }
      if upward { app.swipeUp() } else { app.swipeDown() }
    }
    XCTAssertTrue(element.exists && element.isHittable)
  }
  private func replace(_ field: XCUIElement, with text: String) {
    field.tap()
    if let value = field.value as? String {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
    field.typeText(text)
  }
}
