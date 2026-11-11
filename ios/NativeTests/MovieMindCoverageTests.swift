import Foundation
import XCTest

@testable import TogetherPoC

final class MovieMindCoverageTests: XCTestCase {
  private func json(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
  }
  func testMalformedOrWrongAcknowledgementsCannotConfirmPendingWrites() throws {
    let record = try json([
      "record": ["movieId": "tmdb:99000006"], "mutationId": "mutation_native_123",
    ])
    XCTAssertThrowsError(
      try MovieMindAcknowledgement.decode(
        Data("not JSON".utf8), path: "records/tmdb:99000006", body: record))
    XCTAssertThrowsError(
      try MovieMindAcknowledgement.decode(
        json(["movieId": "tmdb:1", "revision": 1]), path: "records/tmdb:99000006", body: record))
    XCTAssertThrowsError(
      try MovieMindAcknowledgement.decode(
        json(["movieId": "tmdb:99000006"]), path: "records/tmdb:99000006", body: record))
    let event = try json([
      "id": "event_native_123", "sessionId": "session_native_123",
      "editionId": "edition_native_123",
    ])
    XCTAssertThrowsError(
      try MovieMindAcknowledgement.decode(
        json([
          "eventId": "event_native_123", "id": "session_native_123", "editionId": "wrong_cut",
          "coveredMs": 1000,
          "possibleFinished": false,
        ]), path: "watch/events", body: event))
    XCTAssertThrowsError(
      try MovieMindAcknowledgement.decode(
        json(["saved": false]), path: "watch/sessions/session_native_123/completion",
        body: json(["decision": "confirmed"])))
  }
  func testMatchingAcknowledgementsAllowRetryCompletion() throws {
    let record = try json([
      "record": ["movieId": "tmdb:99000006", "rating": NSNull()],
      "mutationId": "mutation_native_123",
    ])
    let saved = try MovieMindAcknowledgement.decode(
      json([
        "movieId": "tmdb:99000006", "revision": 1, "rating": NSNull(),
        "mutationId": "mutation_native_123",
      ]),
      path: "records/tmdb:99000006", body: record)
    XCTAssertEqual(saved["revision"] as? Int, 1)
    let event = try json([
      "id": "event_native_123", "sessionId": "session_native_123",
      "editionId": "edition_native_123",
    ])
    let watched = try MovieMindAcknowledgement.decode(
      json([
        "eventId": "event_native_123", "id": "session_native_123",
        "editionId": "edition_native_123", "coveredMs": 1000,
        "possibleFinished": false,
      ]), path: "watch/events", body: event)
    XCTAssertEqual(watched["possibleFinished"] as? Bool, false)
    XCTAssertNotNil(
      try MovieMindAcknowledgement.decode(
        json(["saved": true]), path: "watch/sessions/session_native_123/completion",
        body: json(["decision": "confirmed"])))
  }
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
