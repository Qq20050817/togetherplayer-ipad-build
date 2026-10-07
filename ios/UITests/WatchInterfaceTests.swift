import XCTest

final class WatchInterfaceTests: XCTestCase {
 func testSubtitleImportReturnsFromFiles() {importSubtitle(fullscreen:false)}
 func testFullscreenSubtitleImportReturnsAndKeepsControlsVisible() {importSubtitle(fullscreen:true)}
 private func importSubtitle(fullscreen:Bool) {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PICKER_SELECTION_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  if fullscreen {let full=app.buttons["全屏观影"].firstMatch;XCTAssertTrue(full.waitForExistence(timeout:15));full.tap()}
  let choose=app.buttons["import-subtitle"].firstMatch
  XCTAssertTrue(choose.waitForExistence(timeout:15));choose.tap()
  let file=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","LOCAL-SUBTITLE-TEST")).firstMatch
  XCTAssertTrue(file.waitForExistence(timeout:12),app.debugDescription);file.tap()
  XCTAssertTrue(app.staticTexts["已加载1条字幕"].waitForExistence(timeout:12),app.debugDescription)
  XCTAssertFalse(app.otherElements["subtitle-document-picker"].exists)
  capture(fullscreen ? "11-fullscreen-subtitle-import" : "10-subtitle-import",app)
 }

 func testSafeEjectControlsAreAvailableInsideRoomSettings() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"];XCTAssertTrue(settings.waitForExistence(timeout:15));settings.tap()
  let eject=app.buttons["safe-eject-usb"]
  for _ in 0..<10 {if eject.isHittable {break};roomForm(app).swipeUp()}
  XCTAssertTrue(eject.isHittable);XCTAssertTrue(eject.isEnabled)
  XCTAssertTrue(app.secureTextFields["usb-management-password"].exists)
  capture("09-native-safe-eject",app)
  // HTTP/auth/action behavior is tested with URLProtocol; no real USB is ejected by UI tests.
 }
 func testTappingUppercaseMP4ReturnsFromFilesAndLoadsLocalSource() {
  selectUppercaseMP4(copy:false)
 }
 func testCompatibleCopyImportReturnsFromFilesAndLoadsLocalSource() {
  selectUppercaseMP4(copy:true)
 }
 private func selectUppercaseMP4(copy:Bool) {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PICKER_SELECTION_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"]
  XCTAssertTrue(settings.waitForExistence(timeout:15));settings.tap()
  let choose=app.buttons[copy ? "import-local-movie-copy" : "choose-local-movie"]
  for _ in 0..<6 {if choose.isHittable {break};roomForm(app).swipeUp()}
  XCTAssertTrue(choose.isHittable);choose.tap()
  let file=app.cells.matching(NSPredicate(format:"label CONTAINS %@","LOCAL-PICKER-TEST")).firstMatch
  XCTAssertTrue(file.waitForExistence(timeout:20),app.debugDescription)
  XCTAssertTrue(file.isHittable,app.debugDescription)
  // Files icon cells include a large metadata area beneath the thumbnail.
  // Tap the document icon, the same activation target a user sees.
  file.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.2)).tap()
  let local=app.staticTexts["本地影片：LOCAL-PICKER-TEST.MP4"]
  XCTAssertTrue(local.waitForExistence(timeout:12),app.debugDescription)
  XCTAssertFalse(app.otherElements["local-movie-document-picker"].exists)
  capture("08-selected-uppercase-mp4",app)
 }
 func testLocalMoviePickerOpensFromRoomSettingsSheet() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"]
  XCTAssertTrue(settings.waitForExistence(timeout:15));settings.tap()
  let choose=app.buttons["choose-local-movie"]
  for _ in 0..<6 {if choose.isHittable {break};roomForm(app).swipeUp()}
  XCTAssertTrue(choose.isHittable);choose.tap()
  let browser=app.otherElements["local-movie-document-picker"]
  let cancel=app.buttons["Cancel"].firstMatch
  XCTAssertTrue(browser.waitForExistence(timeout:8) || cancel.waitForExistence(timeout:3))
  capture("07-local-movie-picker",app)
  if cancel.exists {cancel.tap()}
 }
 func testWatchInterfacePortraitLandscapeAndFullscreen() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"]
  XCTAssertTrue(settings.waitForExistence(timeout:15));capture("01-landscape",app)
  settings.tap()
  let create=app.buttons["创建房间"]
  XCTAssertTrue(create.waitForExistence(timeout:5));capture("02-room-settings",app)
  // Room creation is verified in service tests; this UI test avoids creating live rooms.
  let done=app.buttons["完成"].firstMatch;XCTAssertTrue(done.exists);done.tap()
  let full=app.buttons["全屏观影"].firstMatch;XCTAssertTrue(full.waitForExistence(timeout:5));full.tap()
  let exit=app.buttons["退出全屏"]
  XCTAssertTrue(exit.waitForExistence(timeout:5));capture("03-fullscreen-controls",app)
  // Inactivity removes hit targets; SwiftUI may retain AX nodes in its cache.
  // Debug-only deadline12s accommodates cloud XCTest; Release always uses3s.
  let hidden=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:exit)
  wait(for:[hidden],timeout:16)
  capture("03b-fullscreen-hidden",app)
  app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).tap()
  XCTAssertTrue(exit.waitForExistence(timeout:3))
  let font=app.buttons["弹幕字号"];XCTAssertTrue(font.exists);font.tap()
  XCTAssertTrue(app.sliders["弹幕文字大小"].waitForExistence(timeout:3));capture("04-danmaku-settings",app)
  // Dismiss the popover by tapping outside it, then return to portrait layout.
  app.coordinate(withNormalizedOffset:CGVector(dx:0.1,dy:0.1)).tap()
  app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).tap()
  if !exit.exists {app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).tap()}
  XCTAssertTrue(exit.waitForExistence(timeout:3));exit.tap()
  XCUIDevice.shared.orientation = .portrait
  XCTAssertTrue(settings.waitForExistence(timeout:5));capture("05-portrait",app)
 }
 func testChatDraftSurvivesRoomInterfaceUpdates() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let input=app.textFields["chat-input"].firstMatch
  XCTAssertTrue(input.waitForExistence(timeout:15));input.tap()
  let draft="typing stays local 2026"
  XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:10))
  input.typeText(draft)
  let typed=expectation(for:NSPredicate(format:"value == %@",draft),evaluatedWith:input)
  wait(for:[typed],timeout:10)
  XCTAssertEqual(input.value as? String,draft)
  app.buttons["打开房间与片源"].tap()
  let room=app.textFields["房间编号"]
  XCTAssertTrue(room.waitForExistence(timeout:5));room.tap();room.typeText("test-room")
  app.buttons["完成"].firstMatch.tap()
  XCTAssertTrue(input.waitForExistence(timeout:5))
  XCTAssertEqual(input.value as? String,draft)
  capture("06-chat-draft-after-room-update",app)
 }
 private func roomForm(_ app:XCUIApplication)->XCUIElement {
  let form=app.collectionViews["room-settings-form"].firstMatch
  XCTAssertTrue(form.waitForExistence(timeout:5),app.debugDescription)
  return form
 }
 private func capture(_ name: String,_ app: XCUIApplication) {
  let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
 }
}
