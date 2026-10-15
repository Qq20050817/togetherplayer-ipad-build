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
 func testRestoredBankPublishesOnceAndRevealsOnlyAfterProof() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:root)}
  let movie=root.appendingPathComponent("film.mp4")
  try Data(repeating:0x45,count:400).write(to:movie)
  let hash=try FilmMaterialFingerprint.source(movie)
  let store=FilmQuestionBankStore(directory:root.appendingPathComponent("bank"))
  try await store.save(bank(fingerprint:hash),filmKey:"room-film")
  let runtime=FilmQuestionBankRuntime(store:store)
  runtime.restore(filmKey:"room-film",source:movie,durationMs:120_000)
  for _ in 0..<150 {
   if runtime.active != nil {break}
   try await Task.sleep(nanoseconds:20_000_000)
  }
  XCTAssertNotNil(runtime.active)
  var sent:[String]=[];var revealed:[String]=[]
  func clock(_ t:Double,enabled:Bool=true) {
   runtime.tick(filmKey:"room-film",positionMs:t,durationMs:120_000,
    canPublish:enabled,publish:{sent.append($0.text)},reveal:{revealed.append($0)})
  }
  clock(29_000);clock(30_050)
  XCTAssertEqual(sent.count,1)
  clock(32_000);clock(59_500);XCTAssertTrue(revealed.isEmpty)
  clock(60_100,enabled:false)
  XCTAssertEqual(revealed.count,1)
  XCTAssertTrue(revealed[0].contains("正确答案"))
  clock(60_800)
  XCTAssertEqual(revealed.count,1)
  XCTAssertEqual(sent.count,1)
  // Jump backwards/forwards must not reinject an answered poll.
  clock(4_000);clock(85_000)
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
