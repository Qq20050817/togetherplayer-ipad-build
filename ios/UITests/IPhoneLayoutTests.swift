import XCTest

/// iPhone-only layout regression coverage. Run this class on an iPhone simulator.
final class IPhoneLayoutTests: XCTestCase {
 override func setUp() {
  super.setUp()
  continueAfterFailure = false
 }

 func testPhonePortraitShowsWatchAndCompactAIOverlay() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
  XCUIDevice.shared.orientation = .portrait
  app.launch()

  let ai=app.buttons["watch-header-plot-ai-button"].firstMatch
  XCTAssertTrue(ai.waitForExistence(timeout:20))
  XCTAssertTrue(ai.isHittable,"iPhone portrait must have a tappable AI control")
  XCTAssertTrue(app.buttons["更多房间操作"].exists,"Room actions must remain available via a compact menu")
  ai.tap()
  XCTAssertTrue(app.otherElements["iphone-plot-overlay"].firstMatch.waitForExistence(timeout:10),
   "AI settings must open at readable phone width, not in an unusable narrow side rail")
 }

 func testPhoneBlockingQuestionOpensWithoutManualTap() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_AUTOPAUSE_UI_TEST"]="1"
  XCUIDevice.shared.orientation = .portrait
  app.launch()

  XCTAssertTrue(app.otherElements["iphone-plot-overlay"].firstMatch.waitForExistence(timeout:20))
  XCTAssertTrue(app.staticTexts["刚才的两种解释为何相互矛盾？"].firstMatch.exists,
   "The film question must remain visible and actionable on iPhone")
 }

 func testPhoneLandscapeFullscreenMaintainsMovieAndAIControl() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
  XCUIDevice.shared.orientation = .landscapeLeft
  app.launch()

  let fullscreen=app.buttons["全屏观影"].firstMatch
  XCTAssertTrue(fullscreen.waitForExistence(timeout:20))
  fullscreen.tap()
  XCTAssertTrue(app.otherElements["fullscreen-movie"].firstMatch.waitForExistence(timeout:15))
  let ai=app.buttons["fullscreen-plot-ai-button"].firstMatch
  XCTAssertTrue(ai.waitForExistence(timeout:10))
  ai.tap()
  XCTAssertTrue(app.otherElements["iphone-fullscreen-plot-overlay"].firstMatch.waitForExistence(timeout:10))
 }
}
