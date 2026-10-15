import XCTest

final class WatchInterfaceTests: XCTestCase {
 func testWatchedCleanupReviewsAndDeletesOnlySelectedLocalFiles() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_CLEANUP_UI_TEST"]="1"
  app.launch();XCUIDevice.shared.orientation = .landscapeLeft
  let room=app.buttons["房间与片源"].firstMatch
  XCTAssertTrue(room.waitForExistence(timeout:15));room.tap()
  let scroll=app.scrollViews["room-page-scroll"].firstMatch
  let cleanup=app.buttons["watched-cleanup"].firstMatch
  for _ in 0..<6 {if cleanup.isHittable {break};scroll.swipeUp()}
  XCTAssertTrue(cleanup.isHittable);cleanup.tap()
  let check=app.buttons["cleanup-choose-folder"].firstMatch
  XCTAssertTrue(check.waitForExistence(timeout:5));check.tap()
  let subtitle=app.switches["cleanup-file-CleanupMovie.zh-Hans.srt"].firstMatch
  XCTAssertTrue(subtitle.waitForExistence(timeout:8));XCTAssertTrue(subtitle.label.contains("CleanupMovie.zh-Hans.srt"))
  XCTAssertFalse(app.switches["cleanup-file-Other.srt"].firstMatch.exists)
  let delete=app.buttons["cleanup-delete"].firstMatch
  XCTAssertTrue(delete.waitForExistence(timeout:5));delete.tap()
  let alert=app.alerts.firstMatch
  XCTAssertTrue(alert.waitForExistence(timeout:3));alert.buttons["取消"].tap()
  XCTAssertTrue(delete.exists,"cancelling confirmation must retain the reviewed files")
  delete.tap();XCTAssertTrue(alert.waitForExistence(timeout:3));alert.buttons["删除"].tap()
  let result=app.staticTexts["cleanup-result"].firstMatch
  XCTAssertTrue(result.waitForExistence(timeout:10))
  XCTAssertEqual(result.label,"已删除2个文件。")
  capture("32-watched-file-cleanup",app)
 }
 func testBlockingPlotQuestionPresentsAutomaticallyInWatchPage() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_AUTOPAUSE_UI_TEST"]="1"
  app.launch()
  XCTAssertTrue(app.otherElements["plot-question-drawer"].firstMatch.waitForExistence(timeout:15),
   "A new blocking room question should open without tapping the plot toolbar")
  XCTAssertTrue(app.staticTexts["刚才的两种解释为何相互矛盾？"].firstMatch.exists)
  XCTAssertTrue(app.staticTexts["双方回答后继续"].firstMatch.exists)
 }
 func testPlotAIEntrancesRemainVisibleInWatchAndFullscreen() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
  app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let headerAI=app.buttons["watch-header-plot-ai-button"].firstMatch
  XCTAssertTrue(headerAI.waitForExistence(timeout:15),"普通观影页应有常驻 AI 入口")
  XCTAssertTrue(headerAI.isHittable,"AI 入口不能藏在可横向滚动的工具栏内")
  headerAI.tap()
  XCTAssertTrue(app.navigationBars["剧情推理室"].firstMatch.waitForExistence(timeout:5))
  app.buttons["plot-settings-close"].firstMatch.tap()
  let cardAI=app.buttons["watch-plot-ai-button"].firstMatch
  XCTAssertTrue(cardAI.exists,"播放器控制区应展示 AI 剧情推理")
  enterFullscreen(app)
  let fullscreenAI=app.buttons["fullscreen-plot-ai-button"].firstMatch
  XCTAssertTrue(fullscreenAI.waitForExistence(timeout:5),"全屏控制条顶部应固定显示 AI 入口")
  XCTAssertTrue(fullscreenAI.isHittable)
  fullscreenAI.tap()
  XCTAssertTrue(app.navigationBars["剧情推理室"].firstMatch.waitForExistence(timeout:5))
  app.buttons["plot-settings-close"].firstMatch.tap()
  XCTAssertTrue(app.buttons["退出全屏"].firstMatch.waitForExistence(timeout:5),"关闭 AI 面板不应退出全屏")
 }
 func testAISettingsRailPreservesMovieAndOffersSafeConnectionCheck() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  enterFullscreen(app)
  app.buttons["fullscreen-plot-ai-button"].tap()
  let panel=app.descendants(matching:.any)["plot-settings-panel"].firstMatch
  XCTAssertTrue(panel.waitForExistence(timeout:5))
  let movie=app.otherElements["fullscreen-movie"].firstMatch
  XCTAssertGreaterThan(movie.frame.width,app.frame.width*0.5)
  XCTAssertGreaterThanOrEqual(panel.frame.minX,movie.frame.maxX-2,"settings must reserve their own area")
  capture("30-ai-settings-rail",app)
  app.buttons["plot-chatgpt-settings"].firstMatch.tap()
  XCTAssertTrue(app.navigationBars["ChatGPT 连接与隐私"].waitForExistence(timeout:5))
  let check=app.buttons["plot-connectivity-check"].firstMatch
  for _ in 0..<5 {if check.isHittable {break};app.swipeUp()}
  XCTAssertTrue(check.exists)
  XCTAssertTrue(app.staticTexts["不发送授权信息或剧情内容，不发起推理请求。网络可达不代表授权或额度已通过验证。"].exists)
  app.buttons["plot-auth-close"].tap()
  app.buttons["plot-settings-close"].tap()
  XCTAssertTrue(app.buttons["退出全屏"].waitForExistence(timeout:5))
 }
 func testOpeningAIKeepsTheSamePlaybackCanvasInWatchAndFullscreen() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  func check(_ buttonID:String) {
   let canvas=app.descendants(matching:.any)["playback-canvas-instance"].firstMatch
   XCTAssertTrue(canvas.waitForExistence(timeout:10))
   let identity=canvas.value as? String
   XCTAssertNotNil(identity.flatMap(UUID.init(uuidString:)),"identity must belong to the actual stateful canvas")
   for _ in 0..<3 {
    let open=app.buttons[buttonID].firstMatch;XCTAssertTrue(open.waitForExistence(timeout:5));open.tap()
    let scroll=app.scrollViews["plot-settings-scroll"].firstMatch
    XCTAssertTrue(scroll.waitForExistence(timeout:5))
    XCTAssertEqual(canvas.value as? String,identity,"opening AI must not destroy/recreate the movie canvas")
    app.buttons["plot-settings-close"].firstMatch.tap()
    let closed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:scroll)
    XCTAssertEqual(XCTWaiter.wait(for:[closed],timeout:5),.completed)
    XCTAssertEqual(canvas.value as? String,identity,"closing AI must keep the movie canvas")
    XCTAssertEqual(app.state,.runningForeground)
   }
  }
  check("watch-header-plot-ai-button")
  enterFullscreen(app)
  check("fullscreen-plot-ai-button")
  capture("31-stable-canvas-after-ai-open",app)
 }
 func testAutomaticQuestionReplacesOpenSettingsInWatchAndFullscreen() {
  for fullscreen in [false,true] {
   let app=XCUIApplication()
   app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
   app.launchEnvironment["TOGETHER_PLOT_AUTOPAUSE_IN_SETTINGS_UI_TEST"]="1"
   app.launch();XCUIDevice.shared.orientation = .landscapeLeft
   if fullscreen {enterFullscreen(app)}
   let button=app.buttons[fullscreen ? "fullscreen-plot-ai-button" : "watch-header-plot-ai-button"].firstMatch
   XCTAssertTrue(button.waitForExistence(timeout:15));button.tap()
   let drawer=app.otherElements[fullscreen ? "fullscreen-plot-question-drawer" : "plot-question-drawer"].firstMatch
   XCTAssertTrue(drawer.waitForExistence(timeout:10),"AI settings must not mask a newly published blocking question")
   XCTAssertTrue(app.staticTexts["警方找到的钥匙为什么与证词矛盾？"].firstMatch.exists)
   XCTAssertFalse(app.scrollViews["plot-settings-scroll"].firstMatch.exists)
   XCTAssertTrue(app.buttons["plot-drawer-submit"].firstMatch.exists)
   app.terminate()
  }
 }
 func testQuestionPauseSettingSurvivesPanelDismissalAndRelaunch() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1"
  app.launch();XCUIDevice.shared.orientation = .landscapeLeft
  let open=app.buttons["watch-header-plot-ai-button"].firstMatch
  XCTAssertTrue(open.waitForExistence(timeout:15))
  let settled=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in app.frame.width>app.frame.height && open.frame.minX>app.frame.width*0.75},object:open)
  XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:5),.completed)
  let restingX=open.frame.minX
  open.tap()
  let setting=app.switches["plot-blocking-mode"].firstMatch
  let panelScroll=app.scrollViews["plot-settings-scroll"].firstMatch
  XCTAssertTrue(panelScroll.waitForExistence(timeout:5))
  for _ in 0..<5 {if setting.isHittable {break};panelScroll.swipeUp()}
  XCTAssertTrue(setting.waitForExistence(timeout:5))
  XCTAssertTrue(setting.isEnabled)
  let original=setting.value as? String
  XCTAssertTrue(original=="0" || original=="1")
  // Lazy rows expose the label and switch as one AX frame. Tap the actual
  // trailing switch rather than the non-interactive label at its center.
  setting.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.5)).tap()
  let changed=original=="1" ? "0" : "1"
  let toggled=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",changed),object:setting)
  XCTAssertEqual(XCTWaiter.wait(for:[toggled],timeout:5),.completed)
  XCTAssertEqual(setting.value as? String,changed)
  app.buttons["plot-settings-close"].firstMatch.tap()
  let closed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:panelScroll)
  XCTAssertEqual(XCTWaiter.wait(for:[closed],timeout:5),.completed)
  let returned=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in abs(open.frame.minX-restingX)<2},object:open)
  XCTAssertEqual(XCTWaiter.wait(for:[returned],timeout:5),.completed)
  open.tap()
  XCTAssertTrue(panelScroll.waitForExistence(timeout:5))
  for _ in 0..<5 {if setting.isHittable {break};panelScroll.swipeUp()}
  XCTAssertTrue(setting.waitForExistence(timeout:5))
  XCTAssertEqual(setting.value as? String,changed,"dismissal must preserve the setting")
  app.terminate();app.launch()
  XCTAssertTrue(open.waitForExistence(timeout:15));open.tap()
  XCTAssertTrue(panelScroll.waitForExistence(timeout:5))
  for _ in 0..<5 {if setting.isHittable {break};panelScroll.swipeUp()}
  XCTAssertTrue(setting.waitForExistence(timeout:5))
  XCTAssertEqual(setting.value as? String,changed,"relaunch must preserve the setting")
  setting.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.5)).tap() // Restore the prior preference for other tests.
 }
 func testPlotIntelligencePreviewKeepsFullscreenAndCloudOff() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  enterFullscreen(app)
  let plot=app.buttons["剧情推理"].firstMatch;XCTAssertTrue(plot.waitForExistence(timeout:5));plot.tap()
  // The isolated UI fixture already selects the free mode. Avoid opening
  // the model Picker and obscuring/dismissing this sheet mid-interaction.
  let modePicker=app.descendants(matching:.any)["plot-ai-mode"].firstMatch
  XCTAssertTrue(modePicker.waitForExistence(timeout:8))
  let generate=app.buttons["plot-ai-generate"].firstMatch
  XCTAssertTrue(generate.waitForExistence(timeout:8))
  let movieLoaded=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isEnabled == true"),object:generate)
  XCTAssertEqual(XCTWaiter.wait(for:[movieLoaded],timeout:30),.completed,"real movie must load before generating")
  generate.tap()
  let preview=app.descendants(matching:.any)["plot-question-preview"].firstMatch
  let previewAppeared=preview.waitForExistence(timeout:15)
  let diagnostic=app.staticTexts["plot-ai-reason"].firstMatch
  XCTAssertTrue(previewAppeared,
   "Fallback preview must appear. Diagnostic: \(diagnostic.exists ? diagnostic.label : "reason missing"). UI: \(app.debugDescription)")
  XCTAssertTrue(app.buttons["plot-publish"].exists)
  XCTAssertTrue(app.staticTexts["免费备用题库"].firstMatch.exists)
  capture("21-plot-intelligence-preview",app)
  app.buttons["plot-settings-close"].firstMatch.tap()
  XCTAssertTrue(app.buttons["退出全屏"].firstMatch.waitForExistence(timeout:5))
 }
 // iPadOS 26 can report the old button frame while the first orientation
 // transition is still settling. Confirm the actual fullscreen presentation
 // before querying sliders shared with the ordinary watch screen.
 func testLocalMKVPlaybackControlsSurviveInterleavedTransportActions() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_TRACK_PLAYBACK_TEST"]="1"
  app.launch();XCUIDevice.shared.orientation = .landscapeLeft
  enterFullscreen(app)
  let progress=app.sliders["movie-progress"].firstMatch
  let loaded=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isEnabled == true"),object:progress)
  XCTAssertEqual(XCTWaiter.wait(for:[loaded],timeout:30),.completed)
  let back=app.buttons["后退10秒"].firstMatch
  let forward=app.buttons["前进10秒"].firstMatch
  for _ in 0..<5 {
   app.buttons["playback-toggle"].firstMatch.tap()
   forward.tap();back.tap()
   app.buttons["playback-toggle"].firstMatch.tap()
   progress.adjust(toNormalizedSliderPosition:0.3)
   XCTAssertEqual(app.state,.runningForeground,"transport actions must not terminate the app")
  }
  app.buttons["退出全屏"].firstMatch.tap()
  XCTAssertTrue(app.buttons["全屏观影"].firstMatch.waitForExistence(timeout:5))
 }
 func testFullscreenQuestionRailDoesNotCoverTheMovie() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PLOT_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PLOT_AUTOPAUSE_UI_TEST"]="1"
  app.launch();XCUIDevice.shared.orientation = .landscapeLeft
  XCTAssertTrue(app.otherElements["plot-question-drawer"].firstMatch.waitForExistence(timeout:15))
  enterFullscreen(app)
  let drawer=app.otherElements["fullscreen-plot-question-drawer"].firstMatch, movie=app.otherElements["fullscreen-movie"].firstMatch
  XCTAssertTrue(drawer.waitForExistence(timeout:8));XCTAssertTrue(movie.exists)
  XCTAssertLessThanOrEqual(movie.frame.maxX,drawer.frame.minX+1,"question rail must reserve space beside the film")
  XCTAssertGreaterThan(movie.frame.width,app.windows.firstMatch.frame.width*0.5)
  drawer.buttons["fullscreen-close-plot-question"].firstMatch.tap()
  let closed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:drawer)
  XCTAssertEqual(XCTWaiter.wait(for:[closed],timeout:5),.completed);XCTAssertTrue(movie.exists)
  XCTAssertTrue(app.buttons["待回答"].firstMatch.exists,"closing must keep the unanswered question reachable")
 }
 private func enterFullscreen(_ app:XCUIApplication) {
  let full=app.buttons["全屏观影"].firstMatch
  let movie=app.otherElements["fullscreen-movie"].firstMatch
  XCTAssertTrue(full.waitForExistence(timeout:20))
  let hittable=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isHittable == true"),object:full)
  XCTAssertEqual(XCTWaiter.wait(for:[hittable],timeout:10),.completed)
  for _ in 0..<2 {
   full.tap()
   if movie.waitForExistence(timeout:5) {return}
  }
  XCTFail("点击全屏后必须真正进入全屏画面：\(app.debugDescription)")
 }

 func testFullscreenGestureSurfaceAndDeviceStatus() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_VOICE_GESTURE_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  XCTAssertFalse(app.otherElements["fullscreen-gesture-surface"].exists)
  enterFullscreen(app)
  let surface=app.otherElements["fullscreen-gesture-surface"].firstMatch
  XCTAssertTrue(surface.waitForExistence(timeout:5))
  XCTAssertTrue(app.descendants(matching:.any)["fullscreen-device-status"].firstMatch.exists)
  // Real UIScreen getter is independently displayed; the gesture's requested
  // percentage must not be mistaken for confirmed physical brightness.
  let hardwareReadback=app.staticTexts["fullscreen-brightness-readback"].firstMatch
  let brightnessSlider=app.sliders["fullscreen-brightness-slider"].firstMatch
  XCTAssertTrue(hardwareReadback.exists,"必须显示系统实际读取的屏幕亮度")
  XCTAssertTrue(brightnessSlider.exists,"必须提供独立的系统亮度控制作为排查入口")
  XCTAssertTrue((hardwareReadback.label.filter({$0.isNumber})).count>=1)
  let bar=app.otherElements["fullscreen-control-bar"].firstMatch
  XCTAssertLessThanOrEqual(surface.frame.maxY,bar.frame.minY+1)
  XCTAssertGreaterThan(surface.frame.width,app.windows.firstMatch.frame.width*0.7,"手势层必须覆盖视频宽度")
  XCTAssertGreaterThan(surface.frame.height,app.windows.firstMatch.frame.height*0.25,"手势层高度不能为零")
  let oldBrightness=surface.value as? String ?? ""
  let oldPercent=Int(oldBrightness.filter({$0.isNumber})) ?? 50
  let startY:CGFloat=oldPercent>=60 ? 0.25 : 0.75
  let endY:CGFloat=oldPercent>=60 ? 0.75 : 0.25
  surface.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:startY)).press(forDuration:0.05,thenDragTo:surface.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:endY)))
  let updatedBrightness=surface.value as? String ?? ""
  // Simulator hardware brightness is not guaranteed to update. The exposed
  // gesture target verifies that a real drag reached the movie layer.
  XCTAssertNotEqual(updatedBrightness,oldBrightness,"实际滑动必须到达亮度手势处理器")
  XCTAssertTrue(updatedBrightness.hasPrefix("亮度"))
  XCTAssertTrue(app.buttons["退出全屏"].exists)
  surface.press(forDuration:0.7)
  // XCTest can wait for UI idleness beyond the genuine ten-second deadline.
  // Reveal the idle-hidden controls through the actual movie touch surface.
  let exit=app.buttons["退出全屏"].firstMatch
  if !exit.exists {surface.tap()}
  XCTAssertTrue(exit.waitForExistence(timeout:5))
  exit.tap()
  XCTAssertTrue(app.buttons["全屏观影"].firstMatch.waitForExistence(timeout:6),"退出全屏后主界面必须恢复")
  XCTAssertEqual(app.state,.runningForeground,"退出全屏不能导致 App 闪退")
  XCTAssertFalse(app.otherElements["fullscreen-gesture-surface"].exists)
 }
 func testRepeatedFullscreenExitAfterBrightnessAndLongPressDoesNotCrash() {
  let app=XCUIApplication()
  app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_VOICE_GESTURE_TEST"]="1"
  app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let full=app.buttons["全屏观影"].firstMatch
  XCTAssertTrue(full.waitForExistence(timeout:15))
  for cycle in 0..<3 {
   full.tap()
   let surface=app.otherElements["fullscreen-gesture-surface"].firstMatch
   XCTAssertTrue(surface.waitForExistence(timeout:5))
   if cycle == 1 {
    surface.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.8))
     .press(forDuration:0.05,thenDragTo:surface.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.2)))
   }
   if cycle == 2 {surface.press(forDuration:0.7)}
   let exit=app.buttons["退出全屏"].firstMatch
   XCTAssertTrue(exit.waitForExistence(timeout:5))
   exit.tap()
   XCTAssertTrue(full.waitForExistence(timeout:6),"第\(cycle+1)次退出后必须返回主界面")
   XCTAssertEqual(app.state,.runningForeground,"第\(cycle+1)次退出全屏后 App 不能退出运行")
  }
 }
 func testRoomScrollingKeepsExpandedInputsAndNavigationUsable() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PICKER_SELECTION_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let roomTab=app.buttons["房间与片源"].firstMatch
  XCTAssertTrue(roomTab.waitForExistence(timeout:15));roomTab.tap()
  let scroll=app.scrollViews["room-page-scroll"].firstMatch
  XCTAssertTrue(scroll.waitForExistence(timeout:5))
  let expanded=app.buttons["设置房间影片"].firstMatch
  for _ in 0..<4 {if expanded.isHittable {break};scroll.swipeUp()}
  XCTAssertTrue(expanded.isHittable);expanded.tap()
  let title=app.textFields["room-movie-title"].firstMatch
  XCTAssertTrue(title.waitForExistence(timeout:5))
  let original=title.value as? String
  for _ in 0..<3 {scroll.swipeUp()}
  XCTAssertEqual(app.state,.runningForeground)
  for _ in 0..<5 {if title.isHittable {break};scroll.swipeDown()}
  XCTAssertTrue(title.isHittable,"scrolling back must retain expanded inputs")
  XCTAssertEqual(title.value as? String,original)
  app.buttons["观影"].firstMatch.tap()
  XCTAssertTrue(app.buttons["watch-header-plot-ai-button"].waitForExistence(timeout:5))
 }
 func testRoomCardsKeepActionsVisibleAndRemovedToolsAbsent() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_PICKER_SELECTION_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let settings=app.buttons["打开房间与片源"];XCTAssertTrue(settings.waitForExistence(timeout:15));settings.tap()
  XCTAssertTrue(app.staticTexts["房间管理"].waitForExistence(timeout:5))
  for removed in ["苹果 HDR / Atmos 测试片","仅替换本机为本地影片（好友继续在线）","模拟断线3秒","iPad Atmos测试片音轨"] {XCTAssertFalse(app.buttons[removed].exists)}
  XCTAssertTrue(app.buttons["创建房间"].isHittable);XCTAssertGreaterThanOrEqual(app.buttons["创建房间"].frame.height,44)
  let copy=app.buttons["复制房间编号"];XCTAssertTrue(copy.isHittable);copy.tap()
  capture("18-room-cards-landscape",app)
  let choose=app.buttons["choose-local-movie"]
  for _ in 0..<6 {if choose.isHittable {break};app.swipeUp()}
  XCTAssertTrue(choose.isHittable);XCTAssertGreaterThanOrEqual(choose.frame.height,44)
  XCUIDevice.shared.orientation = .portrait
  capture("19-room-cards-portrait",app)
 }
 func testFullscreenVoiceHoldKeepsPreviewAndIndependentTools() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_VOICE_GESTURE_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  enterFullscreen(app)
  let bar=app.otherElements["fullscreen-control-bar"].firstMatch
  let hold=bar.descendants(matching:.any)["hold-voice-danmaku"].firstMatch
  XCTAssertTrue(hold.waitForExistence(timeout:5));XCTAssertTrue(hold.isHittable)
  hold.press(forDuration:1.5)
  let result=bar.textFields["voice-result"].firstMatch
  XCTAssertTrue(result.waitForExistence(timeout:5),app.debugDescription)
  XCTAssertEqual(result.value as? String,"语音手势测试结果")
  XCTAssertTrue(bar.buttons["confirm-voice-danmaku"].exists)
  XCTAssertGreaterThan(hold.frame.midX,app.frame.width*0.7)
  capture("16-voice-hold-preview",app)
  bar.buttons["cancel-voice-danmaku"].tap()
  let tools=[bar.buttons["音轨"].firstMatch,bar.buttons["字幕"].firstMatch,bar.buttons["fullscreen-import-subtitle"],bar.buttons["fullscreen-subtitle-adjustments"],bar.buttons["弹幕字号"],bar.buttons["弹幕速度"]]
  for tool in tools {
   // AX snapshots can outlast the idle timer. Perform a real harmless header
   // tap between checks, just as a user keeps the controls active by touching.
   if !bar.exists {app.otherElements["fullscreen-movie"].firstMatch.tap()}
   app.staticTexts["fullscreen-movie-title"].firstMatch.tap()
   XCTAssertTrue(tool.isHittable);XCTAssertEqual(tool.frame.width,96,accuracy:1);XCTAssertEqual(tool.frame.height,36,accuracy:1)
  }
  bar.buttons["后退10秒"].tap()
  let action=bar.staticTexts["playback-action-feedback"].firstMatch
  XCTAssertTrue(action.waitForExistence(timeout:2));XCTAssertFalse(action.label.isEmpty)
  bar.buttons["弹幕速度"].tap()
  let speed=app.sliders["弹幕速度"];XCTAssertTrue(speed.waitForExistence(timeout:5));speed.adjust(toNormalizedSliderPosition:0.2)
  // Open options remain usable past the ten-second idle deadline.
  sleep(11)
  XCTAssertTrue(speed.exists);XCTAssertTrue(speed.isHittable)
  capture("17-danmaku-speed",app)
 }

 func testVoiceEntryDoesNotActivateMicrophoneOutsideRoom() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let enable=app.buttons["enable-voice-danmaku"].firstMatch
  XCTAssertTrue(enable.waitForExistence(timeout:15));XCTAssertFalse(enable.isEnabled)
  XCTAssertTrue(app.staticTexts["语音弹幕未开启"].exists)
  XCTAssertFalse(app.textFields["voice-result"].exists)
 }

 func testFullscreenProgressAndRealMovieAdjustment() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launchEnvironment["TOGETHER_TRACK_PLAYBACK_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  enterFullscreen(app)
  let fullscreenMovie=app.otherElements["fullscreen-movie"].firstMatch
  func revealControls() {
   if !app.otherElements["fullscreen-control-bar"].firstMatch.exists {fullscreenMovie.tap()}
   XCTAssertTrue(app.otherElements["fullscreen-control-bar"].firstMatch.waitForExistence(timeout:5))
  }
  revealControls()
  let progress=app.otherElements["fullscreen-control-bar"].sliders["movie-progress"].firstMatch
  let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isEnabled == true"),object:progress)
  XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:30),.completed)
  let currentCaption=app.staticTexts["这是简体字幕测试"].firstMatch
  XCTAssertTrue(currentCaption.waitForExistence(timeout:15),app.debugDescription)
  if app.buttons["暂停"].firstMatch.exists {app.buttons["暂停"].firstMatch.tap()}
  // Decoder/snapshot startup can consume the normal ten-second idle window.
  // Reveal real controls again and never adjust the covered watch-page slider.
  revealControls()
  progress.adjust(toNormalizedSliderPosition:0.5)
  let seek=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '剩余 00:06' OR label == '剩余 00:07'"),object:app.staticTexts["playback-remaining"].firstMatch)
  XCTAssertEqual(XCTWaiter.wait(for:[seek],timeout:8),.completed)
  revealControls()
  app.buttons["fullscreen-subtitle-adjustments"].tap()
  let movie=app.otherElements["subtitle-live-movie"].firstMatch
  XCTAssertTrue(movie.waitForExistence(timeout:5));XCTAssertGreaterThan(movie.frame.width,app.frame.width*0.5)
  let text=app.staticTexts["这是简体字幕测试"].firstMatch
  XCTAssertTrue(text.waitForExistence(timeout:8),app.debugDescription)
  let before=text.frame
  app.sliders["字幕垂直位置"].adjust(toNormalizedSliderPosition:0.6)
  let moved=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in text.frame.minY < before.minY-30},object:text)
  XCTAssertEqual(XCTWaiter.wait(for:[moved],timeout:5),.completed)
  capture("20-real-movie-subtitle-adjustment",app)
  app.buttons["close-subtitle-adjustments"].tap()
  XCTAssertTrue(progress.waitForExistence(timeout:5))
 }
 func testSubtitleAdjustmentPanelChangesValuesAndResets() {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let adjust=app.buttons["subtitle-adjustments"].firstMatch
  XCTAssertTrue(adjust.waitForExistence(timeout:15));adjust.tap()
  XCTAssertTrue(app.otherElements["subtitle-live-movie"].waitForExistence(timeout:5))
  XCTAssertLessThan(app.otherElements["subtitle-live-movie"].frame.maxX,app.frame.width-250)
  let delay=app.steppers["subtitle-delay"]
  XCTAssertTrue(delay.waitForExistence(timeout:5))
  delay.buttons["subtitle-delay-Increment"].tap()
  XCTAssertTrue(app.staticTexts["字幕偏移 +0.1 秒"].exists)
  app.sliders["字幕垂直位置"].adjust(toNormalizedSliderPosition:0.4)
  app.sliders["字幕文字大小"].adjust(toNormalizedSliderPosition:0.7)
  let family=app.segmentedControls["subtitle-font-family"]
  for _ in 0..<5 {if family.buttons["圆体"].isHittable {break};app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeUp()}
  XCTAssertTrue(family.buttons["圆体"].waitForExistence(timeout:5),app.debugDescription)
  revealFormControl(family.buttons["圆体"],app:app)
  family.buttons["圆体"].tap()
  XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"isSelected == true"),object:family.buttons["圆体"])],timeout:3) == .completed)
  let weight=app.segmentedControls["subtitle-font-weight"]
  for _ in 0..<5 {if weight.buttons["细体"].isHittable {break};app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeUp()}
  revealFormControl(weight.buttons["细体"],app:app)
  weight.buttons["细体"].tap();XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"isSelected == true"),object:weight.buttons["细体"])],timeout:3) == .completed)
  let line=app.sliders["字幕行间距"]
  for _ in 0..<5 {if line.isHittable {break};app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeUp()}
  app.sliders["字幕字间距"].adjust(toNormalizedSliderPosition:0.7)
  line.adjust(toNormalizedSliderPosition:0.5)
  XCTAssertFalse(app.staticTexts["字间距 +0.00"].exists)
  XCTAssertFalse(app.staticTexts["行间距 +0.0"].exists)
  XCTAssertTrue(app.staticTexts["subtitle-style-preview"].exists)
  let reset=app.buttons["reset-subtitle-adjustments"]
  for _ in 0..<5 {if reset.isHittable {break};app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeUp()}
  XCTAssertTrue(reset.isHittable);reset.tap()
  XCTAssertTrue(app.staticTexts["字间距 +0.00"].exists)
  XCTAssertTrue(app.staticTexts["行间距 +0.0"].exists)
  XCTAssertTrue(app.segmentedControls["subtitle-font-family"].buttons["系统"].isSelected)
  XCTAssertTrue(app.segmentedControls["subtitle-font-weight"].buttons["常规"].isSelected)
  capture("15-subtitle-adjustments",app)
  // Form virtualizes distant rows. Scroll to each default before asserting it.
  let size=app.staticTexts["字幕字号 24"]
  for _ in 0..<8 {if size.exists {break};app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeDown()}
  XCTAssertTrue(size.exists,app.debugDescription)
  let position=app.staticTexts["距画面底部 7%"]
  for _ in 0..<8 {if position.exists {break};app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeDown()}
  XCTAssertTrue(position.exists,app.debugDescription)
  app.buttons["close-subtitle-adjustments"].tap()
  app.buttons["全屏观影"].firstMatch.tap()
  let fullscreenAdjust=app.buttons["fullscreen-subtitle-adjustments"]
  XCTAssertTrue(fullscreenAdjust.waitForExistence(timeout:5),app.debugDescription)
  XCTAssertTrue(fullscreenAdjust.isHittable,app.debugDescription);fullscreenAdjust.tap()
  XCTAssertTrue(app.sliders["字幕文字大小"].waitForExistence(timeout:5))
  app.buttons["close-subtitle-adjustments"].tap()
  XCTAssertTrue(app.buttons["退出全屏"].waitForExistence(timeout:5))
 }
 // SwiftUI reports partially clipped segments as hittable even underneath
 // the sheet navigation bar. Require the entire tap target in the content viewport.
 private func revealFormControl(_ target:XCUIElement,app:XCUIApplication) {
  let form=app.collectionViews.containing(.segmentedControl,identifier:"subtitle-font-family").firstMatch
  XCTAssertTrue(form.exists)
  for _ in 0..<8 {
   let viewport=form.frame;let bounds=target.frame
   let edge=form.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.45))
   if bounds.minY < viewport.minY+80 {edge.press(forDuration:0.1,thenDragTo:edge.withOffset(CGVector(dx:0,dy:180)),withVelocity:.slow,thenHoldForDuration:0.3)}
   else if bounds.maxY > viewport.maxY-24 {edge.press(forDuration:0.1,thenDragTo:edge.withOffset(CGVector(dx:0,dy:-180)),withVelocity:.slow,thenHoldForDuration:0.3)}
   else {XCTAssertTrue(target.isHittable);return}
  }
  XCTAssertGreaterThanOrEqual(target.frame.minY,form.frame.minY+80)
  XCTAssertLessThanOrEqual(target.frame.maxY,form.frame.maxY-24)
 }
 func testSubtitleImportReturnsFromFiles() {importSubtitle(fullscreen:false)}
 func testFullscreenSubtitleImportReturnsAndKeepsControlsVisible() {importSubtitle(fullscreen:true)}
 private func importSubtitle(fullscreen:Bool) {
  let app=XCUIApplication();app.launchEnvironment["TOGETHER_UI_TEST"]="1"
  app.launchEnvironment["TOGETHER_SUBTITLE_SELECTION_TEST"]="1";app.launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  if fullscreen {let full=app.buttons["全屏观影"].firstMatch;XCTAssertTrue(full.waitForExistence(timeout:15));full.tap()}
  let choose=app.buttons[fullscreen ? "fullscreen-import-subtitle" : "import-subtitle"].firstMatch
  XCTAssertTrue(choose.waitForExistence(timeout:15));XCTAssertTrue(choose.isHittable);choose.tap()
  let file=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","LOCAL-SUBTITLE-TEST")).firstMatch
  XCTAssertTrue(file.waitForExistence(timeout:90),app.debugDescription);file.tap()
  XCTAssertTrue(app.staticTexts["已加载1条字幕"].waitForExistence(timeout:12),app.debugDescription)
  if fullscreen {
   let movie=app.otherElements["fullscreen-movie"].firstMatch;XCTAssertTrue(movie.exists)
   let exit=app.buttons["退出全屏"].firstMatch
   // DocumentsUI/AX snapshots can take longer than the idle deadline after
   // import has finished. Idle hiding is correct; controls must remain reachable.
   if !exit.isHittable {movie.tap()}
   XCTAssertTrue(exit.isHittable)
  }
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
  // The first simulator DocumentsUI provider can start slowly; select the real file cell.
  XCTAssertTrue(file.waitForExistence(timeout:90),app.debugDescription);file.tap()
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
  let section=app.buttons["设置房间影片"].firstMatch
  if !app.buttons["set-room-media"].exists {section.tap()}
  let button=app.buttons["set-room-media"]
  XCTAssertTrue(button.waitForExistence(timeout:5))
  // Scroll from within the actual viewport, not from an offscreen button.
  let viewport=app.scrollViews.containing(.button,identifier:"set-room-media").firstMatch
  for _ in 0..<4 {
   if button.isHittable {break}
   viewport.swipeUp()
  }
  let visible=XCTNSPredicateExpectation(predicate:NSPredicate(format:"isHittable == true"),object:button)
  XCTAssertEqual(XCTWaiter.wait(for:[visible],timeout:8),.completed)
  XCTAssertTrue(button.isEnabled);button.tap()
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
  let file=app.cells.matching(NSPredicate(format:"label CONTAINS %@", "LOCAL-PICKER-TEST")).firstMatch
  // The first simulator DocumentsUI provider can start slowly; select the real file cell.
  XCTAssertTrue(file.waitForExistence(timeout:90),app.debugDescription)
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
  XCTAssertTrue(exit.waitForExistence(timeout:5))
  let movie=app.otherElements["fullscreen-movie"].firstMatch;let bar=app.otherElements["fullscreen-control-bar"].firstMatch
  XCTAssertTrue(bar.waitForExistence(timeout:5));XCTAssertLessThanOrEqual(movie.frame.maxY,bar.frame.minY+1)
  XCTAssertLessThan(bar.frame.height,150)
  let mic=bar.buttons["enable-voice-danmaku"].firstMatch;XCTAssertTrue(mic.exists);XCTAssertGreaterThan(mic.frame.midX,app.frame.width*0.7)
  capture("03-fullscreen-controls",app)
  // Inactivity removes hit targets; SwiftUI may retain AX nodes in its cache.
  // Hide only after ten seconds with no interaction.
  let hidden=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:exit)
  wait(for:[hidden],timeout:16)
  capture("03b-fullscreen-hidden",app)
  // Hit the movie touch surface itself; an app-wide tap can land in another
  // overlay or an offscreen toolbar as the simulator rotates.
  let gesture=app.otherElements["fullscreen-gesture-surface"].firstMatch
  XCTAssertTrue(gesture.waitForExistence(timeout:5))
  gesture.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).tap()
  XCTAssertTrue(exit.waitForExistence(timeout:5),"轻点影片后必须能重新显示退出全屏按钮")
  let font=app.buttons["弹幕字号"];XCTAssertTrue(font.waitForExistence(timeout:5));font.tap()
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
  XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
  input.typeText(draft)
  let committed=expectation(for:NSPredicate(format:"value == %@",draft),evaluatedWith:input)
  wait(for:[committed],timeout:10)
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
  // Capture the display directly: app-scoped capture can time out after a
  // document picker returns to the fullscreen AVPlayer view on hosted runners.
  let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
 }
}
