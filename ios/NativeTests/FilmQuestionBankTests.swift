import XCTest
@testable import TogetherPoC

final class FilmQuestionBankTests:XCTestCase {
 private func sample(trigger:Int=30_000,reveal:Int=60_000)->FilmQuestionBank {
  FilmQuestionBank(schemaVersion:1,title:"悬疑测试影片",year:2026,edition:"院线版",durationMs:120_000,
   sourceFingerprint:String(repeating:"a",count:64),subtitleFingerprint:String(repeating:"b",count:64),
   questions:[FilmBankQuestion(id:"q1",triggerAtMs:trigger,revealAtMs:reveal,
    type:"prediction",question:"证人说的两次时间为什么不同？",
    options:["他忘记了时间","他在刻意隐瞒","文件被人修改"],
    answerIndex:1,
    evidence:[FilmBankEvidence(kind:"subtitle",startMs:22_000,endMs:24_000,text:"证人声称自己在八点前离开")],
    revealEvidence:[FilmBankEvidence(kind:"subtitle",startMs:50_000,endMs:52_000,text:"录像证实证人当晚仍然在场")],
    explanation:"后面出现的录像澄清了矛盾。",confidence:0.92,qualityScore:93)])
 }
 func testBankRoundTripAndOptionalEdition() throws {
  let bank=sample()
  let data=try JSONEncoder().encode(bank)
  XCTAssertEqual(try FilmBankCodec.decode(data),bank)
  XCTAssertEqual(FilmBankCodec.question(bank.questions[0],blocking:true).choices.count,3)
 }
 func testRejectsSpoilerEvidenceInQuestion() throws {
  let bank=sample(trigger:20_000)
  XCTAssertThrowsError(try FilmBankCodec.validate(bank))
 }
 func testRejectsTooEarlyReveal() throws {
  let bank=sample(trigger:30_000,reveal:24_000)
  XCTAssertThrowsError(try FilmBankCodec.validate(bank))
 }
 func testMovieCutMustMatch() {
  XCTAssertTrue(FilmBankCodec.matches(sample(),playbackDuration:120_000))
  XCTAssertFalse(FilmBankCodec.matches(sample(),playbackDuration:130_000))
 }
 func testArchiveIsValidZipWithManifestAndSubtitle() {
  guard let bytes=FilmMaterialZip.make([("manifest.json",Data("{}".utf8)),("subtitles/whole-film.srt",Data("1\n".utf8))]) else {
   return XCTFail("ZIP missing")
  }
  XCTAssertTrue(bytes.starts(with:[0x50,0x4b,0x03,0x04]))
  XCTAssertGreaterThan(bytes.count,80)
  XCTAssertTrue(bytes.suffix(22).starts(with:[0x50,0x4b,0x05,0x06]))
 }
 func testSamplingIncludesQuietVisualGaps() {
  let subtitles=SubtitleDocument([SubtitleCue(start:0,end:10,text:"台词"),
    SubtitleCue(start:80,end:90,text:"台词"),
    SubtitleCue(start:110,end:115,text:"结束")])
  let times=FilmMaterialExporter.selectedTimes(duration:180,subtitles:subtitles)
  XCTAssertTrue(times.contains(where:{abs($0-45)<2}))
  XCTAssertTrue(times.count<180)
 }
 func testBankSurvivesColdLoad() async throws {
  let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:path)}
  let store=FilmQuestionBankStore(directory:path)
  let bank=sample()
  try await store.save(bank,filmKey:"same-movie")
  let loaded=await store.load(filmKey:"same-movie")
  XCTAssertEqual(bank,loaded)
  let missing=await store.load(filmKey:"different-movie")
  XCTAssertNil(missing)
 }
}
