import Foundation
import XCTest

@testable import TogetherPoC

final class MovieMindJournalTests: XCTestCase {
  private func body(
    _ rating: Double? = nil, status: String = "seen", original: [String: Any] = [:],
    deleted: Bool = false
  ) throws -> [String: Any] {
    let data = try MovieMindJournal.recordBody(
      movie: "tmdb:100", original: original, status: status,
      rating: rating, comment: "我的真实短评", date: "2026-11-12", together: true,
      likes: "悬疑，反转,悬疑", dislikes: "", experience: "不恐怖", favorite: false, sharedWish: true,
      deleted: deleted)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  func testUnratedExperienceAndReviewNeverInventScore() throws {
    let sent = try body()
    let record = try XCTUnwrap(sent["record"] as? [String: Any])
    XCTAssertTrue(record["rating"] is NSNull)
    XCTAssertEqual(record["comment"] as? String, "我的真实短评")
    XCTAssertEqual(record["experience"] as? [String], ["不恐怖"])
    XCTAssertEqual(record["likes"] as? [String], ["悬疑", "反转"])
    XCTAssertEqual(record["status"] as? String, "seen")
  }
  func testExplicitHalfScoreAndRevisionSurviveEditing() throws {
    let old: [String: Any] = [
      "movieId": "tmdb:100", "revision": 7, "createdAt": "fixture-created", "source": "manual",
    ]
    let sent = try body(8.5, status: "rewatch", original: old)
    let record = try XCTUnwrap(sent["record"] as? [String: Any])
    XCTAssertEqual(sent["expectedRevision"] as? Int, 7)
    XCTAssertEqual(record["rating"] as? Double, 8.5)
    XCTAssertEqual(record["createdAt"] as? String, "fixture-created")
    XCTAssertEqual(record["status"] as? String, "rewatch")
    XCTAssertNotNil(sent["mutationId"] as? String)
    XCTAssertThrowsError(try body(7.2))
    XCTAssertThrowsError(try body(.infinity))
    XCTAssertThrowsError(try body(-0.5))
  }
  func testWithdrawalIsExplicitAndCannotReassignOtherWork() throws {
    let sent = try body(original: ["movieId": "tmdb:100", "revision": 3], deleted: true)
    XCTAssertEqual((sent["record"] as? [String: Any])?["deleted"] as? Bool, true)
    XCTAssertEqual(sent["expectedRevision"] as? Int, 3)
    XCTAssertThrowsError(try body(original: ["movieId": "tmdb:101", "revision": 3]))
  }
  func testAllStatusesRemainExplicit() throws {
    for item in MovieMindJournal.statuses {
      XCTAssertEqual(
        (try body(status: item.0)["record"] as? [String: Any])?["status"] as? String, item.0)
    }
    XCTAssertThrowsError(try body(status: "technical_failure"))
  }
  func testManualIdentityAndContentEvidenceStaySeparate() throws {
    let data = try MovieMindJournal.workBody(
      id: "manual:fixture_2000", title: "同名", originalTitle: "", year: 2000,
      runtime: 0, present: "悬疑", absent: "血腥")
    let movie = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tags = try XCTUnwrap(movie["tags"] as? [String: [String: Any]])
    XCTAssertEqual(tags["悬疑"]?["state"] as? String, "present")
    XCTAssertEqual(tags["血腥"]?["state"] as? String, "absent")
    XCTAssertNil(tags["突脸"])
    XCTAssertEqual(movie["id"] as? String, "manual:fixture_2000")
    XCTAssertThrowsError(
      try MovieMindJournal.workBody(
        id: "manual:fixture_2000", title: "同名", originalTitle: "", year: 2000,
        runtime: 90, present: "血腥", absent: "血腥"))
  }
  func testSearchFindsAliasesButIdentityDoesNotUseTitle() throws {
    let raw =
      #"{"id":"tmdb:100","title":"译名甲","year":2000,"originalTitle":"Original","aliases":["译名乙"]}"#
      .data(using: .utf8)!
    let movie = try JSONDecoder().decode(MovieMindWork.self, from: raw)
    XCTAssertTrue(movie.matches("译名乙"))
    XCTAssertTrue(movie.matches("tmdb:100"))
    XCTAssertFalse(movie.matches("不存在"))
    XCTAssertTrue(MovieMindJournal.validID("tmdb:100"))
    XCTAssertFalse(MovieMindJournal.validID("/private/movie.mkv"))
  }
  func testConflictMergeKeepsDraftReviewTagsAndWithdrawalWithoutChangingServerIdentity() {
    let current: [String: Any] = [
      "movieId": "tmdb:100", "revision": 5, "source": "manual", "createdAt": "original",
    ]
    let draft: [String: Any] = [
      "movieId": "tmdb:200", "revision": 1, "source": "wrong", "rating": NSNull(),
      "comment": "updated", "likes": ["反转"], "watchedOn": "2026-11-12", "deleted": true,
    ]
    let merged = MovieMindJournal.mergeDraft(draft, into: current)
    XCTAssertEqual(merged["movieId"] as? String, "tmdb:100")
    XCTAssertEqual(merged["revision"] as? Int, 5)
    XCTAssertEqual(merged["source"] as? String, "manual")
    XCTAssertEqual(merged["likes"] as? [String], ["反转"])
    XCTAssertEqual(merged["watchedOn"] as? String, "2026-11-12")
    XCTAssertEqual(merged["deleted"] as? Bool, true)
    XCTAssertTrue(merged["rating"] is NSNull)
  }

}
