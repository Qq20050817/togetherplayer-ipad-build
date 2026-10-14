import XCTest
import AVFoundation
@testable import TogetherPoC

final class SeekBurstTests: XCTestCase {
 func testRapidSeekBurstRetainsFinalValidTargetOnly() {
  var queue=SeekRequestBuffer()
  for index in 0..<1000 {
   XCTAssertTrue(queue.replace(Double(index)*200,duration:120_000))
  }
  XCTAssertEqual(queue.takeLatest(),120_000)
  XCTAssertNil(queue.takeLatest())
  XCTAssertFalse(queue.replace(.nan,duration:120_000))
  XCTAssertFalse(queue.replace(.infinity,duration:120_000))
  XCTAssertNil(queue.takeLatest())
  XCTAssertTrue(queue.replace(-1000,duration:120_000))
  XCTAssertEqual(queue.takeLatest(),0)
  XCTAssertTrue(queue.replace(80_000,duration:120_000))
  queue.clear()
  XCTAssertNil(queue.takeLatest(),"A replaced movie must not replay an older seek")
  XCTAssertTrue(queue.replace(500_000_000,duration:0))
  XCTAssertEqual(queue.takeLatest(),86_400_000)
 }

 @MainActor func testRapidTenSecondTapsAccumulateWhileServerAcknowledgementIsPending() throws {
  let credentials:[String:Any]=["roomId":"seek-test","userId":"host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  defer {UserDefaults.standard.removeObject(forKey:"credentials")}
  var sent:[[String:Any]]=[]
  let client=TestClient(automaticallyConnect:false,messageSender:{sent.append($0)})
  let before:[String:Any]=["state":"paused","position":0,"updatedAt":0,"playbackRate":1]
  let room:[String:Any]=["roomId":"seek-test","hostId":"host","mediaUrl":"https://example.org/movie.mp4","title":"测试片源","version":1,"executeAt":0,"state":"paused","position":0,"updatedAt":0,"playbackRate":1,"before":before]
  client.receive(["type":"WELCOME","room":room,"lastSequence":0],t4:0)
  client.clock.add(0,0,0,0)
  client.skipBy(10_000)
  client.skipBy(10_000)
  client.skipBy(10_000)
  let first=try XCTUnwrap(sent.first(where:{$0["type"] as? String=="SEEK"}))
  XCTAssertEqual(first["position"] as? Double,10_000)
  XCTAssertEqual(sent.filter{$0["type"] as? String=="SEEK"}.count,1)
  let sequence=try XCTUnwrap(first["sequence"] as? Int64)
  client.receive(["type":"STATE","room":room,"ackUserId":"host","ackSequence":sequence],t4:0)
  let controls=sent.filter{$0["type"] as? String=="SEEK"}
  XCTAssertEqual(controls.count,2,"Only the latest queued position should be transmitted")
  XCTAssertEqual(controls.last?["position"] as? Double,30_000)
 }

 @MainActor func testSpeedHoldChangesLocalRateBeforeNetworkConfirmation() throws {
  let credentials:[String:Any]=["roomId":"speed-test","userId":"host","token":String(repeating:"a",count:64)]
  UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:credentials),forKey:"credentials")
  defer {UserDefaults.standard.removeObject(forKey:"credentials")}
  var sent:[[String:Any]]=[]
  let client=TestClient(automaticallyConnect:false,messageSender:{sent.append($0)})
  let before:[String:Any]=["state":"playing","position":0,"updatedAt":0,"playbackRate":1]
  let room:[String:Any]=["roomId":"speed-test","hostId":"host","mediaUrl":"https://example.org/movie.mp4","version":1,"executeAt":0,"state":"playing","position":0,"updatedAt":0,"playbackRate":1,"before":before]
  client.receive(["type":"WELCOME","room":room,"lastSequence":0],t4:0)
  client.setSpeedHold(true)
  XCTAssertEqual(client.adapter.player.defaultRate,2)
  XCTAssertTrue(sent.contains(where:{$0["type"] as? String=="SPEED_HOLD"}))
  client.setSpeedHold(false)
  XCTAssertEqual(client.adapter.player.defaultRate,1)
 }
}
