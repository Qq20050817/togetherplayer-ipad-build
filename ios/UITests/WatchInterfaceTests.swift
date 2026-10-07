import XCTest

final class WatchInterfaceTests: XCTestCase {
 func testSubtitleImportReturnsFromFiles() {importSubtitle(fullscreen:false)}
 func testFullscreenSubtitleImportReturnsAndKeepsControlsVisible() {importSubtitle(fullscreen:true)}
 private func importSubtitle(fullscreen:Bool) {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_SUBTITLE_SELECTION_TEST"]="1";app.launch()
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


 func testLocalQualitySelectionRequiresReviewedConfirmation() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_LOCAL_QUALITY_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"];XCTAssertTrue(settings.waitForExistence(timeout:15));settings.tap()
  let choose=app.buttons["choose-local-movie"]
  for _ in 0..<6 {if choose.isHittable {break};app.swipeUp()}
  XCTAssertTrue(choose.isHittable);choose.tap()
  // The underlying room title also contains the stem. Exclude its MKV name
  // and target the actual MP4 document in the system picker.
  let file=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ AND NOT label CONTAINS %@","LOCAL-PICKER-TEST",".mkv")).firstMatch
  XCTAssertTrue(file.waitForExistence(timeout:12));file.tap()
  let confirm=app.buttons["确认相同剪辑，使用此画质"]
  XCTAssertTrue(confirm.waitForExistence(timeout:10));capture("13-local-quality-confirmation",app);confirm.tap()
  XCTAssertFalse(confirm.exists)
  app.buttons["完成"].firstMatch.tap()
  let notice=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","已确认同一影片的另一画质，时长核对通过")).firstMatch
  XCTAssertTrue(notice.waitForExistence(timeout:12),app.debugDescription)
  capture("14-local-quality-matched",app)
 }
 func testFullscreenKeyboardKeepsMovieAboveComposer() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_ROOM_MEDIA_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let full=app.buttons["全屏观影"].firstMatch;XCTAssertTrue(full.waitForExistence(timeout:15));full.tap()
  let compose=app.buttons["发弹幕"];XCTAssertTrue(compose.waitForExistence(timeout:5));compose.tap()
  let input=app.textFields["danmaku-input"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText("Keep movie visible")
  let movie=app.otherElements["fullscreen-movie"].firstMatch
  XCTAssertTrue(movie.exists,app.debugDescription)
  XCTAssertGreaterThan(movie.frame.height,80)
  XCTAssertLessThanOrEqual(movie.frame.maxY,input.frame.minY)
  // iPad keyboard AX bounds can still be in portrait coordinates after rotation.
  // The movie/composer comparison uses app coordinates; screenshots verify the
  // actual docked keyboard region as well.
  XCTAssertTrue(app.keyboards.firstMatch.exists)
  XCTAssertEqual(input.value as? String,"Keep movie visible")
  capture("10-fullscreen-keyboard-landscape",app)
  XCUIDevice.shared.orientation = .portrait
  XCTAssertTrue(input.waitForExistence(timeout:5));XCTAssertGreaterThan(movie.frame.height,80)
  XCTAssertLessThanOrEqual(movie.frame.maxY,input.frame.minY)
  capture("11-fullscreen-keyboard-portrait",app)
  app.buttons["close-danmaku-input"].tap()
  XCTAssertTrue(app.buttons["退出全屏"].waitForExistence(timeout:5))
 }
 func testRemainingTimeLabelVisibleInFullscreenAndWatchCard() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let remaining=app.staticTexts["playback-remaining"].firstMatch
  XCTAssertTrue(remaining.waitForExistence(timeout:15));XCTAssertTrue(remaining.isHittable)
  XCTAssertEqual(remaining.label,"剩余 --:--")
  app.buttons["全屏观影"].firstMatch.tap()
  XCTAssertTrue(remaining.waitForExistence(timeout:5));XCTAssertTrue(remaining.isHittable)
  capture("12-remaining-time",app)
 }
 func testSetRoomMediaButtonShowsValidationBesideAction() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_ROOM_MEDIA_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"]
  XCTAssertTrue(settings.waitForExistence(timeout:15));settings.tap()
  // The media action initially sits at the sheet's lower edge on this iPad.
  // Bring the action and its inline response into the viewport before tapping.
  let button=app.buttons["set-room-media"]
  XCTAssertTrue(button.waitForExistence(timeout:5))
  let start=button.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
  start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:-180)),withVelocity:.slow,thenHoldForDuration:0.5)
  XCTAssertTrue(button.isHittable);XCTAssertTrue(button.isEnabled);button.tap()
  let feedback=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","片源链接无效或包含账户凭据")).firstMatch
  XCTAssertTrue(feedback.waitForExistence(timeout:5));XCTAssertTrue(feedback.isHittable)
  capture("09-room-media-feedback",app)
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
  for _ in 0..<6 {if choose.isHittable {break};app.swipeUp()}
  XCTAssertTrue(choose.isHittable);choose.tap()
  let file=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@", "LOCAL-PICKER-TEST")).firstMatch
  XCTAssertTrue(file.waitForExistence(timeout:12),app.debugDescription)
  file.tap()
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
  for _ in 0..<6 {if choose.isHittable {break};app.swipeUp()}
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
  input.typeText(draft)
  XCTAssertEqual(input.value as? String,draft)
  app.buttons["打开房间与片源"].tap()
  let room=app.textFields["房间编号"]
  XCTAssertTrue(room.waitForExistence(timeout:5));room.tap();room.typeText("test-room")
  app.buttons["完成"].firstMatch.tap()
  XCTAssertTrue(input.waitForExistence(timeout:5))
  XCTAssertEqual(input.value as? String,draft)
  capture("06-chat-draft-after-room-update",app)
 }
 private func capture(_ name: String,_ app: XCUIApplication) {
  let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
 }
}
