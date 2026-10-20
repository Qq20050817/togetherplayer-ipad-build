import XCTest
@testable import TogetherPoC

final class FilmEndingEvidenceTests:XCTestCase {
 func testTwelveMinuteWindowAndShortFilmFullCoverage() {
  let long=FilmTailSamplingPlan.dense(duration:7_200)
  XCTAssertEqual(long.first,6_480)
  XCTAssertEqual(long.last,7_198)
  XCTAssertEqual(long.count,360)
  let short=FilmTailSamplingPlan.dense(duration:90)
  XCTAssertEqual(short.first,0)
  XCTAssertEqual(short.last,88)
  XCTAssertEqual(short.count,45)
 }
 func testHalfSecondBoundaryCoversBothSides() {
  let samples=FilmTailSamplingPlan.boundary(at:100,duration:120)
  XCTAssertEqual(samples.count,21)
  XCTAssertEqual(samples.first,95)
  XCTAssertEqual(samples.last,105)
 }
 func testCreditStartAndPostCreditReturnProduceUnverifiedCandidates() {
  let stream:[(Int,Bool)]=[(110_000,false),(112_000,false),(114_000,true),
     (116_000,true),(118_000,true),(120_000,false),(122_000,false),
     (124_000,true),(126_000,true)]
  let result=FilmCreditsDetector.candidates(stream)
  XCTAssertEqual(result.map(\.kind),["possibleCreditsStart","possiblePostCreditsScene","possibleCreditsStart"])
  XCTAssertEqual(result.first?.atMs,114_000)
  XCTAssertEqual(result[1].atMs,120_000)
 }
 func testTimeGateRejectsRepeatedPTSButAcceptsStationaryFilmFrames() {
  let previous=[(2_000,2_000),(4_000,4_000)]
  XCTAssertNil(FilmFrameTimeGate.rejection(requestedMs:6_000,actualMs:6_000,intervalMs:2_000,previous:previous,durationMs:30_000))
  XCTAssertNotNil(FilmFrameTimeGate.rejection(requestedMs:6_000,actualMs:4_000,intervalMs:2_000,previous:previous,durationMs:30_000))
  XCTAssertNotNil(FilmFrameTimeGate.rejection(requestedMs:6_000,actualMs:4_500,intervalMs:2_000,previous:previous,durationMs:30_000))
  XCTAssertNotNil(FilmFrameTimeGate.rejection(requestedMs:5_000,actualMs:3_900,intervalMs:2_000,previous:previous,durationMs:30_000))
  XCTAssertNotNil(FilmFrameTimeGate.rejection(requestedMs:6_000,actualMs:nil,intervalMs:2_000,previous:previous,durationMs:30_000))
 }
 func testBackwardExpansionReachesEarlierMinutes() {
  XCTAssertEqual(FilmTailSamplingPlan.backward(from:720).first,660)
  XCTAssertEqual(FilmTailSamplingPlan.backward(from:720).count,30)
  XCTAssertEqual(FilmTailSamplingPlan.backward(from:25).first,0)
 }
}
