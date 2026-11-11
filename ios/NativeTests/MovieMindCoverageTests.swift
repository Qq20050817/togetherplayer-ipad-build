import XCTest

@testable import TogetherPoC

final class MovieMindCoverageTests: XCTestCase {
  func testCatchupRateChangesStayInOneActualMediaBatch() {
    var c = MovieMindCoverage()
    c.sample(position: 0, now: 0, playing: true, rate: 1)
    c.sample(position: 1000, now: 1000, playing: true, rate: 1)
    c.sample(position: 2500, now: 2000, playing: true, rate: 2)
    c.sample(position: 4500, now: 3000, playing: true, rate: 2)
    let b = c.drain()!
    XCTAssertEqual(b.elapsedMs, 3000)
    XCTAssertEqual(b.intervals, [.init(start: 0, end: 4500)])
    XCTAssertEqual(b.rate, 2)
  }
  func testExplicitSeekAndTailJumpDoNotCountSkippedMedia() {
    var c = MovieMindCoverage()
    c.sample(position: 0, now: 0, playing: true, rate: 1)
    c.sample(position: 1000, now: 1000, playing: true, rate: 1)
    c.discontinuity()
    c.sample(position: 99000, now: 1100, playing: true, rate: 1)
    c.sample(position: 100000, now: 2100, playing: true, rate: 1)
    let b = c.drain()!
    XCTAssertEqual(b.intervals, [.init(start: 0, end: 1000), .init(start: 99000, end: 100000)])
    XCTAssertEqual(b.elapsedMs, 2000)
  }
  func testPauseBufferAndLongGapDoNotManufactureCoverage() {
    var c = MovieMindCoverage()
    c.sample(position: 0, now: 0, playing: true, rate: 1)
    c.sample(position: 1000, now: 1000, playing: false, rate: 1)
    c.sample(position: 9000, now: 9000, playing: true, rate: 1)
    XCTAssertNil(c.drain())
    c.sample(position: 10000, now: 10000, playing: true, rate: 1)
    XCTAssertEqual(c.drain()?.elapsedMs, 1000)
  }
  func testDoubleSpeedRecordsActualMediaIntervalOnce() {
    var c = MovieMindCoverage()
    c.sample(position: 0, now: 0, playing: true, rate: 2)
    c.sample(position: 2000, now: 1000, playing: true, rate: 2)
    let b = c.drain()!
    XCTAssertEqual(b.elapsedMs, 1000)
    XCTAssertEqual(b.intervals, [.init(start: 0, end: 2000)])
    XCTAssertEqual(b.rate, 2)
  }
}
