import XCTest
@testable import TogetherPoC

final class SubtitleVerificationPlanTests: XCTestCase {
 func testThreeDialogueSamplesPerThird() {
  let captions = (0..<90).map { n in
   SubtitleCue(start:Double(n)*12+2,end:Double(n)*12+5,text:"第\(n)句对白")
  }
  let samples = SubtitleVerificationPlan.samples(document:SubtitleDocument(captions),duration:1080)
  XCTAssertEqual(samples.count,9)
  XCTAssertEqual(samples.map(\.index),Array(1...9))
  for third in 0..<3 {
   XCTAssertEqual(samples[(third*3)..<(third*3+3)].count,3)
   XCTAssertTrue(samples[(third*3)..<(third*3+3)].allSatisfy {
    $0.subtitleStartSeconds >= Double(third)*360 && $0.subtitleStartSeconds < Double(third+1)*360
   })
  }
  XCTAssertTrue(samples.allSatisfy{$0.durationSeconds==10 && $0.startSeconds>=0 && $0.startSeconds+10<=1080})
 }
 func testNoInventedDialogueSamples() {
  let doc=SubtitleDocument([SubtitleCue(start:10,end:14,text:"你好")])
  XCTAssertTrue(SubtitleVerificationPlan.samples(document:doc,duration:600).isEmpty)
 }
 func testRejectsInvalidDuration() {
  XCTAssertTrue(SubtitleVerificationPlan.samples(document:SubtitleDocument([]),duration:.infinity).isEmpty)
 }
 func testAudioOnlySamplingNeedsNoSubtitleDocument() {
  let samples=SubtitleVerificationPlan.audioOnlySamples(duration:7200)
  XCTAssertEqual(samples.count,9)
  XCTAssertEqual(samples.map(\.index),Array(1...9))
  for (index,sample) in samples.enumerated() {
   let third=index/3
   let lower=Double(third)*2400
   let upper=Double(third+1)*2400
   XCTAssertGreaterThanOrEqual(sample.startSeconds,lower)
   XCTAssertLessThanOrEqual(sample.startSeconds+10,upper)
   XCTAssertEqual(sample.durationSeconds,10)
  }
 }
 func testAudioOnlyRecoveryPositionsStayInTheirOwnThird() {
  for sample in SubtitleVerificationPlan.audioOnlySamples(duration:180) {
   let positions=SubtitleVerificationPlan.audioOnlyCandidateStarts(
    for:sample,duration:180)
   XCTAssertGreaterThanOrEqual(positions.count,1)
   XCTAssertLessThanOrEqual(positions.count,3)
   XCTAssertEqual(positions.first,sample.startSeconds)
   let third=(sample.index-1)/3
   XCTAssertTrue(positions.allSatisfy {
    $0>=Double(third)*60 && $0+10<=Double(third+1)*60
   })
  }
 }
 func testAudioOnlyRejectsUnknownDurationAndSilentPCM() {
  XCTAssertTrue(SubtitleVerificationPlan.audioOnlySamples(duration:0).isEmpty)
  XCTAssertTrue(SubtitleVerificationPlan.audioOnlySamples(duration:.infinity).isEmpty)
  XCTAssertTrue(SubtitleVerificationPlan.audioOnlySamples(duration:89).isEmpty)
  XCTAssertEqual(FilmAudioSpeechActivity.score(
   pcm16le:Data(repeating:0,count:10*16000*2)),0)
 }
 func testModulatedVoicedCandidateOutscoresSilence() {
  var bytes=Data(capacity:10*16000*2)
  for i in 0..<(10*16000) {
   let active=(i/8000)%2==0
   let amplitude=active ? ((i/1600)%2==0 ? 6000 : 2000) : 0
   let value:Int16=(i/24)%2==0 ? Int16(amplitude) : Int16(-amplitude)
   bytes.append(UInt8(truncatingIfNeeded:value))
   bytes.append(UInt8(truncatingIfNeeded:Int(value)>>8))
  }
  XCTAssertGreaterThan(FilmAudioSpeechActivity.score(pcm16le:bytes),0.035)
 }
}
