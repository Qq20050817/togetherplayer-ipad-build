import XCTest
import AVFoundation
@testable import TogetherPoC
private final class ClockPlayer:AVPlayer {
 var seconds=0.0
 override func currentTime()->CMTime {CMTime(seconds:seconds,preferredTimescale:600)}
}
@MainActor final class PlaybackClockTests:XCTestCase {
 func testDisplayedTimeReadsNativeClockWithoutRoomOrConnection() async throws {
  let player=ClockPlayer();let monitor=PlaybackMonitor(player:player)
  player.seconds=5;monitor.refresh();XCTAssertEqual(monitor.position,5)
  player.seconds=8
  try await Task.sleep(nanoseconds:650_000_000)
  XCTAssertEqual(monitor.position,8,"common-mode watchdog must refresh without any room state")
  player.seconds=2;monitor.refresh();XCTAssertEqual(monitor.position,2,"seek refresh reads actual native time")
 }
}
