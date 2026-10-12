import XCTest
@testable import TogetherPoC

final class ChatTimestampTests:XCTestCase {
 func testLocalDayLabelsFromServerUnixMilliseconds() {
  var calendar=Calendar(identifier:.gregorian)
  calendar.timeZone=TimeZone(secondsFromGMT:0)!
  let iso=ISO8601DateFormatter()
  func date(_ value:String)->Date {iso.date(from:value)!}
  func label(_ value:String)->String {
   ChatTimestamp.label(milliseconds:date(value).timeIntervalSince1970*1000,
    now:date("2026-10-13T01:20:00Z"),calendar:calendar)
  }
  XCTAssertEqual(label("2026-10-13T00:05:00Z"),"00:05")
  XCTAssertEqual(label("2026-10-12T23:40:00Z"),"昨天 23:40")
  XCTAssertEqual(label("2026-10-11T08:09:00Z"),"10月11日 08:09")
  XCTAssertEqual(label("2025-12-31T23:59:00Z"),"2025年12月31日 23:59")
  XCTAssertEqual(ChatTimestamp.label(milliseconds:0,calendar:calendar),"")
  XCTAssertEqual(ChatTimestamp.label(milliseconds:.nan,calendar:calendar),"")
 }
}
