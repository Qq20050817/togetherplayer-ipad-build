import XCTest

/// iPhone-only layout regression coverage. Run on a physical-size iPhone simulator.
@MainActor final class IPhoneLayoutTests: XCTestCase {
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
  XCTAssertTrue(ai.isHittable,"Portrait phone needs tappable AI controls")
  XCTAssertTrue(app.buttons["更多房间操作"].exists,"Room sharing and leaving must stay reachable on phone")
  ai.tap()
  XCTAssertTrue(app.otherElements["iphone-plot-overlay"].firstMatch.waitForExistence(timeout:10),
   "Phone AI panel must be readable and occupy the available viewport")
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
   "Automatic blocking question must be visible on iPhone")
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

 func testPhoneFilmCatalogActionsAccessible() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  XCUIDevice.shared.orientation = .portrait
  app.launch()
  XCTAssertTrue(app.buttons["watch-header-plot-ai-button"].firstMatch.waitForExistence(timeout:20))
  let refresh=app.buttons["usb-playlist-refresh"].firstMatch
  XCTAssertTrue(refresh.exists,"Phone movie catalog must retain the USB refresh action")
  let capture=XCTAttachment(screenshot:app.screenshot())
  capture.name="iphone-portrait-film-catalog"
  capture.lifetime = .keepAlways
  add(capture)
 }
}
