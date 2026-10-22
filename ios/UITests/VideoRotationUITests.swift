import XCTest
@MainActor final class VideoRotationUITests:XCTestCase {
 func testRotationPersistsAcrossFullscreenAndImportLivesInSubtitleMenu() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_TRACK_PLAYBACK_TEST"]="1";app.launch()
  let rotate=app.buttons["rotate-video"];XCTAssertTrue(rotate.waitForExistence(timeout:20))
  XCTAssertEqual(rotate.value as? String,"0°");rotate.tap();XCTAssertEqual(rotate.value as? String,"90°")
  app.buttons["全屏观影"].tap()
  let full=app.buttons["fullscreen-rotate-video"];XCTAssertTrue(full.waitForExistence(timeout:10));XCTAssertEqual(full.value as? String,"90°")
  full.tap();XCTAssertEqual(full.value as? String,"180°")
  XCTAssertFalse(app.buttons["fullscreen-import-subtitle"].exists)
  app.buttons["退出全屏"].tap()
  XCTAssertTrue(rotate.waitForExistence(timeout:10));XCTAssertEqual(rotate.value as? String,"180°")
  rotate.tap();rotate.tap();XCTAssertEqual(rotate.value as? String,"0°")
  XCTAssertFalse(app.buttons["import-subtitle"].exists)
  app.buttons["subtitle-menu"].tap()
  let importButton=app.buttons["import-subtitle"];XCTAssertTrue(importButton.waitForExistence(timeout:10))
  let capture=XCTAttachment(screenshot:app.screenshot());capture.name="unified-subtitle-menu";capture.lifetime = .keepAlways;add(capture)
  importButton.tap()
  let cancel=app.buttons.matching(NSPredicate(format:"label == 'Cancel' OR label == '取消'")).firstMatch
  XCTAssertTrue(cancel.waitForExistence(timeout:15));cancel.tap()
  XCTAssertTrue(rotate.waitForExistence(timeout:10))
 }
}
