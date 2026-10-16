import XCTest
@testable import TogetherPoC

@MainActor final class FilmQuestionBankRuntimeTests:XCTestCase {
 private func bank(fingerprint:String)->FilmQuestionBank {
  FilmQuestionBank(schemaVersion:1,title:"可验证的悬疑影片",year:2026,edition:"院线版",
   durationMs:120_000,sourceFingerprint:fingerprint,subtitleFingerprint:nil,
   questions:[FilmBankQuestion(id:"q1",triggerAtMs:30_000,revealAtMs:60_000,
    type:"prediction",question:"现场遗落的手套究竟意味着什么？",
    options:["属于证人","属于嫌疑人","是警方遗漏的"],answerIndex:1,
    evidence:[FilmBankEvidence(kind:"subtitle",startMs:20_000,endMs:25_000,text:"手套是谁留下的？")],
    revealEvidence:[FilmBankEvidence(kind:"subtitle",startMs:52_000,endMs:57_000,text:"录像里的人遗落了手套")],
    explanation:"录像提供了事实证据",confidence:0.9,qualityScore:94)])
 }
 func testRestoredBankPublishesOnceAndKeepsAnswersSecretDuringMovie() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:root)}
  let movie=root.appendingPathComponent("film.mp4")
  try Data(repeating:0x45,count:400).write(to:movie)
  let hash=try FilmMaterialFingerprint.source(movie)
  let store=FilmQuestionBankStore(directory:root.appendingPathComponent("bank"))
  try await store.save(bank(fingerprint:hash),filmKey:"room-film")
  let runtime=FilmQuestionBankRuntime(store:store,progressStore:FilmBankProgressStore(directory:root.appendingPathComponent("progress")))
  runtime.restore(filmKey:"room-film",source:movie,durationMs:120_000)
  for _ in 0..<150 {
   if runtime.active != nil {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertNotNil(runtime.active)
  var sent:[String]=[];var revealed:[String]=[]
  func clock(_ t:Double,enabled:Bool=true) async {
   runtime.tick(filmKey:"room-film",positionMs:t,durationMs:120_000,
    canPublish:enabled,publish:{sent.append($0.text)},reveal:{revealed.append($0.text);runtime.acknowledgeReveal($0.id)})
   await runtime.waitForProgress()
  }
  await clock(29_000);await clock(30_050)
  XCTAssertEqual(sent.count,1)
  await clock(32_000);await clock(59_500);XCTAssertTrue(revealed.isEmpty)
  await clock(60_100,enabled:false)
  XCTAssertTrue(revealed.isEmpty,"Future evidence time cannot send solutions mid-film")
  await clock(60_800)
  XCTAssertTrue(revealed.isEmpty)
  XCTAssertEqual(sent.count,1)
  // Jump backwards/forwards must not reinject an answered poll.
  await clock(4_000);await clock(85_000)
  XCTAssertEqual(sent.count,1)
  let unrelated=root.appendingPathComponent("different.mp4")
  try Data(repeating:0x46,count:400).write(to:unrelated)
  runtime.restore(filmKey:"room-film",source:unrelated,durationMs:120_000)
  XCTAssertNil(runtime.active,"A changed source is disabled immediately while fingerprinting")
  for _ in 0..<100 {
   if runtime.status.contains("不匹配") {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertNil(runtime.active)
 }
 func testNarrativeCreditsMarkerFinishesWithoutWatchingCreditsOrJumpSpoilers() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:root)}
  let movie=root.appendingPathComponent("story-end.mp4")
  try Data(repeating:0x31,count:512).write(to:movie)
  let hash=try FilmMaterialFingerprint.source(movie)
  let store=FilmQuestionBankStore(directory:root.appendingPathComponent("bank"))
  var generatedBank=bank(fingerprint:hash)
  generatedBank.storyEndMs=90_000
  generatedBank.filmReview=FilmReview(
   plotBeats:[FilmReviewBeat(title:"谜团",detail:"手套引出案件主线"),FilmReviewBeat(title:"真相",detail:"录像确定了物证的真实来源")],
   characters:[FilmReviewCharacter(name:"调查者",role:"通过核对监控追查证人动机")],
   theme:"故事借一件不起眼的物证，提醒观众不要仅凭直觉判定他人的动机。",
   discussion:"你认为调查者应该先去确认哪一条线索，才能尽量避免误判？"
  )
  try await store.save(generatedBank,filmKey:"room-film")
  var monotonic=1000.0
  let runtime=FilmQuestionBankRuntime(store:store,progressStore:FilmBankProgressStore(directory:root.appendingPathComponent("progress")),uptimeNow:{monotonic})
  runtime.restore(filmKey:"room-film",source:movie,durationMs:120_000)
  await runtime.waitForRestore()
  XCTAssertNotNil(runtime.active)
  var paused=0,sent:[String]=[],recaps:[String]=[]
  func clock(_ ms:Double,playing:Bool=true) async {
   monotonic+=1
   runtime.tick(filmKey:"room-film",positionMs:ms,durationMs:120_000,
    canPublish:playing,canReveal:true,revealPositionMs:ms,
    canFinish:playing,pauseAtStoryEnd:{paused+=1},participantNames:["alice":"玩家A"],
    publish:{sent.append($0.text)},
    reveal:{part in
     if part.id.hasPrefix("bank-final:") {recaps.append(part.text)}
     runtime.acknowledgeReveal(part.id)
    })
   await runtime.waitForProgress()
  }
  await clock(29_500);await clock(30_500)
  XCTAssertEqual(sent.count,1)
  let options=generatedBank.questions[0].options
  runtime.observePoll(["id":"poll1","question":generatedBank.questions[0].question,
   "options":options,"revealed":false])
  runtime.observePoll(["id":"poll1","question":generatedBank.questions[0].question,
   "options":options,"revealed":true,"answers":["alice":options[1]]])
  await runtime.waitForProgress()
  // Seek directly to the last second of the story: must never unveil.
  await clock(89_500,playing:false)
  await clock(90_500)
  XCTAssertTrue(runtime.finalReport.isEmpty)
  XCTAssertEqual(paused,0)
  await clock(76_000,playing:false)
  for time in stride(from:77_000,through:91_000,by:1_000) {
   await clock(Double(time))
  }
  XCTAssertEqual(paused,1)
  XCTAssertTrue(runtime.finalReport.contains("正确答案"))
  XCTAssertTrue(runtime.finalReport.contains("🎞 全片复盘"))
  XCTAssertTrue(runtime.finalReport.contains("剧情节点：1｜谜团"))
  XCTAssertTrue(runtime.finalReport.contains("观后讨论："))
  XCTAssertTrue(runtime.finalReport.contains("玩家A"))
  XCTAssertTrue(recaps.joined().contains("观影结算"))
  await clock(92_000,playing:false)
  XCTAssertEqual(paused,1)
  XCTAssertFalse(runtime.finalReport.isEmpty)
 }
 func testStoryEndMarkerMustFollowLastReveal() throws {
  var invalid=bank(fingerprint:String(repeating:"a",count:64))
  invalid.storyEndMs=45_000
  XCTAssertThrowsError(try FilmBankCodec.validate(invalid))
  invalid.storyEndMs=90_000
  XCTAssertNoThrow(try FilmBankCodec.validate(invalid))
 }
 func testFFmpegDecodesKnownVideoFrameWithoutLivePlayer() throws {
  let movie=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
  try TestMovieFixture.mp4.write(to:movie)
  defer {try? FileManager.default.removeItem(at:movie)}
  let sampler=try XCTUnwrap(FilmFFmpegFrameSampler(url:movie))
  let frame=try XCTUnwrap(sampler.image(at:0))
  XCTAssertGreaterThan(frame.width,1)
  XCTAssertGreaterThan(frame.height,1)
 }
}
