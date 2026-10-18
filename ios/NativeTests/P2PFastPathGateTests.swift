import XCTest
@testable import TogetherPoC

final class P2PFastPathGateTests: XCTestCase {
 private func hint(room: String = "abcd1234", sender: String = "host", version: Int64 = 7,
                   sequence: Int64 = 1, positionMs: Double = 500, issuedAtMs: Double = 100_000) -> P2PControlHint {
  P2PControlHint(roomID: room, senderUserID: sender, roomVersion: version,
                 sequence: sequence, action: .pause, positionMs: positionMs, issuedAtMs: issuedAtMs)
 }
 private func configured() -> P2PFastPathGate {
  var gate = P2PFastPathGate()
  gate.attach(roomID: "abcd1234", hostUserID: "host", localUserID: "guest", serverVersion: 7)
  return gate
 }
 func testUnverifiedP2PIsNeverTrusted() {
  var gate = configured()
  XCTAssertEqual(gate.admit(hint(), nowMs: 101_000), .noVerifiedPeer)
  gate.verifyPeer(fromAuthoritativeRoster: true)
  XCTAssertEqual(gate.admit(hint(), nowMs: 101_000), .noVerifiedPeer)
  gate.setChannelAlive(true)
  XCTAssertEqual(gate.admit(hint(), nowMs: 101_000), .accepted)
  gate.setChannelAlive(false)
  XCTAssertEqual(gate.admit(hint(sequence: 2), nowMs: 101_000), .noVerifiedPeer)
 }
 func testRejectsWrongRoomAndWrongSender() {
  var gate = configured()
  gate.verifyPeer(fromAuthoritativeRoster: true)
  gate.setChannelAlive(true)
  XCTAssertEqual(gate.admit(hint(room: "other"), nowMs: 101_000), .roomMismatch)
  XCTAssertEqual(gate.admit(hint(sender: "intruder"), nowMs: 101_000), .wrongSender)
  XCTAssertEqual(gate.admit(hint(), nowMs: 101_000), .accepted)
 }
 func testSequenceVersionAndReplayProtections() {
  var gate = configured()
  gate.verifyPeer(fromAuthoritativeRoster: true)
  gate.setChannelAlive(true)
  XCTAssertEqual(gate.admit(hint(), nowMs: 101_000), .accepted)
  XCTAssertEqual(gate.admit(hint(), nowMs: 101_000), .staleSequence)
  XCTAssertEqual(gate.admit(hint(sequence: 2, positionMs: -1), nowMs: 101_000), .invalidCommand)
  XCTAssertEqual(gate.admit(hint(version: 6, sequence: 2), nowMs: 101_000), .staleVersion)
  gate.serverState(version: 8)
  XCTAssertEqual(gate.admit(hint(version: 7, sequence: 2), nowMs: 101_000), .staleVersion)
  XCTAssertEqual(gate.admit(hint(version: 8, sequence: 2), nowMs: 101_000), .accepted)
 }
 func testExpiredAndUntrustedClockAreRejected() {
  var gate = configured()
  gate.verifyPeer(fromAuthoritativeRoster: true)
  gate.setChannelAlive(true)
  XCTAssertEqual(gate.admit(hint(), nowMs: 106_000), .expired)
  XCTAssertEqual(gate.admit(hint(), nowMs: 97_000), .expired)
  XCTAssertEqual(gate.admit(hint(), nowMs: 102_000), .accepted)
 }
 func testRoomSwitchResetsPeerVerificationAndSequences() {
  var gate = configured()
  gate.verifyPeer(fromAuthoritativeRoster: true)
  gate.setChannelAlive(true)
  XCTAssertEqual(gate.admit(hint(), nowMs: 100_000), .accepted)
  gate.attach(roomID: "room9999", hostUserID: "newhost", localUserID: "guest", serverVersion: 1)
  XCTAssertFalse(gate.peerVerified)
  XCTAssertEqual(gate.lastSequence, 0)
  XCTAssertEqual(gate.admit(hint(room: "room9999",sender: "newhost",version: 1), nowMs: 100_000), .noVerifiedPeer)
 }
 func testHostDoesNotAdmitItsOwnSpeculativeCommand() {
  var gate = P2PFastPathGate()
  gate.attach(roomID: "abcd1234", hostUserID: "host", localUserID: "host", serverVersion: 7)
  gate.verifyPeer(fromAuthoritativeRoster: true)
  gate.setChannelAlive(true)
  XCTAssertEqual(gate.admit(hint(), nowMs: 100_000), .wrongSender)
 }
}
