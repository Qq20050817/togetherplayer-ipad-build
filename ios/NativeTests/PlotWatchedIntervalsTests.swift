import XCTest
@testable import TogetherPoC

final class PlotWatchedIntervalsTests:XCTestCase {
 func testRewindBeforeAnEarlierRangeCannotConstructReversedBounds() {
  var ranges=[8.0...10.0]
  PlotWatchedIntervals.record(&ranges,from:1,to:1.15)
  XCTAssertEqual(ranges,[8...10,1...1.15])
 }
 func testRewatchInsideAnEarlierRangeDoesNotEraseItsEnd() {
  var ranges=[8.0...10.0]
  PlotWatchedIntervals.record(&ranges,from:8.5,to:8.7)
  XCTAssertEqual(ranges,[8...10])
 }
 func testContinuousPlaybackExtendsOnlyTheWatchedInterval() {
  var ranges=[8.0...10.0]
  PlotWatchedIntervals.record(&ranges,from:9.95,to:10.15)
  XCTAssertEqual(ranges,[8...10.15])
 }
 func testSkippedGapAndInvalidTimesDoNotBecomeWatchedEvidence() {
  var ranges=[1.0...2.0]
  for pair in [(Double.nan,3.0),(1.0,Double.infinity),(-1.0,0.0),(3.0,2.0),(2.0,20.0)] {
   PlotWatchedIntervals.record(&ranges,from:pair.0,to:pair.1)
  }
  XCTAssertEqual(ranges,[1...2])
  PlotWatchedIntervals.record(&ranges,from:20,to:20.15)
  XCTAssertEqual(ranges,[1...2,20...20.15])
  XCTAssertFalse(ranges.contains{$0.contains(10)},"jumped-over plot must not enter AI evidence")
 }
 func testRepeatedDisjointPlaybackKeepsBoundedHistory() {
  var ranges:[ClosedRange<Double>]=[]
  for index in 0..<1000 {let start=Double(index*4);PlotWatchedIntervals.record(&ranges,from:start,to:start+1)}
  XCTAssertEqual(ranges.count,500);XCTAssertEqual(ranges.last,3996...3997)
 }
}
